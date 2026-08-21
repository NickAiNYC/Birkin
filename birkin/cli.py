"""
birkin.cli
==========

The ``birkin`` command-line entry point.

Two subcommands matter for the vertical slice:

* ``birkin verify <package.json>`` — offline verification of an exported
  run package. No Birkin server required.
* ``birkin demo`` — runs the full end-to-end vertical slice in <60s and
  prints the canonical AUTHENTIC block.
* ``birkin attack <1|2|3>`` — runs one of the three attack demos and
  prints the tampered / blocked verdict.

Everything else (``run``, ``keys``, ``identity``) is intentionally tiny:
the slice is about *the evidence chain*, not a full operator surface.
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path
from typing import Optional

import typer

# Allow ``birkin demo`` and ``birkin attack`` to import the demos/ package,
# which lives next to the birkin package in the project root (not installed).
_PROJECT_ROOT = Path(__file__).resolve().parent.parent
if str(_PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(_PROJECT_ROOT))

from . import __version__
from .crypto import SigningKey
from .verify import render_report, verify_file

app = typer.Typer(
    name="birkin",
    help="Birkin — the open Agent Authorization & Evidence Layer.",
    no_args_is_help=True,
    add_completion=False,
)


@app.command()
def version() -> None:
    """Print the Birkin version."""
    typer.echo(f"birkin {__version__}")


@app.command()
def verify(
    package: str = typer.Argument(..., help="Path to a birkin run package (.json)"),
    quiet: bool = typer.Option(False, "--quiet", "-q", help="Print verdict only"),
) -> None:
    """Offline-verify a Birkin run package."""
    path = Path(package)
    if not path.exists():
        typer.echo(f"error: package not found: {package}", err=True)
        raise typer.Exit(code=2)
    report = verify_file(path)
    if quiet:
        typer.echo(report.verdict)
    else:
        typer.echo(render_report(report))
    if report.verdict != "AUTHENTIC":
        raise typer.Exit(code=1)


@app.command()
def demo(
    out: Optional[str] = typer.Option(
        None, "--out", "-o", help="Write the run package to this path"
    ),
    show_events: bool = typer.Option(
        False, "--show-events", help="Print the full event ledger"
    ),
) -> None:
    """Run the end-to-end vertical slice in <60s and print the verdict."""
    from demos.end_to_end import run_demo

    run_demo(out_path=out, show_events=show_events)


@app.command()
def attack(
    n: int = typer.Argument(..., help="Attack number: 1, 2, or 3"),
    out: Optional[str] = typer.Option(
        None, "--out", "-o", help="Write the tampered package to this path"
    ),
) -> None:
    """Run one of the three attack demonstrations.

    1. Prompt injection / goal hijacking
    2. Unauthorized / privilege-escalating tool use
    3. Skill or policy tampering
    """
    from demos import attacks

    if n == 1:
        attacks.attack_1_prompt_injection(out_path=out)
    elif n == 2:
        attacks.attack_2_privilege_escalation(out_path=out)
    elif n == 3:
        attacks.attack_3_policy_tampering(out_path=out)
    else:
        typer.echo(f"error: unknown attack {n}", err=True)
        raise typer.Exit(code=2)


@app.command()
def keys() -> None:
    """Generate and print a fresh Birkin control-plane signing key."""
    sk = SigningKey.generate()
    typer.echo(json.dumps(
        {
            "private_b64": sk.private_b64,
            "public_b64": sk.public_b64,
            "algorithm": "Ed25519",
        },
        indent=2,
    ))
    typer.echo(
        "# store private_b64 as BIRKIN_SIGNING_KEY (env). Distribute public_b64.",
        err=True,
    )


@app.command()
def run(
    tool: str = typer.Option(..., "--tool", help="Tool name"),
    args_json: str = typer.Option("{}", "--args", help="JSON args"),
    agent_id: str = typer.Option("demo-agent", "--agent-id"),
    out: str = typer.Option("run_package.json", "--out", "-o"),
    policy: Optional[str] = typer.Option(
        None, "--policy", help="Path to policy JSON (default: bundled default)"
    ),
) -> None:
    """Run a single tool under Birkin governance and export a run package."""
    from .engine import Engine
    from .policy import PolicySpec, DEFAULT_POLICY_PATH
    from .adapters.hermes import HermesAdapter

    sk_env = os.environ.get("BIRKIN_SIGNING_KEY")
    sk = SigningKey.from_private_b64(sk_env) if sk_env else SigningKey.generate()

    spec = PolicySpec.load(policy or DEFAULT_POLICY_PATH)
    adapter = HermesAdapter()
    identity = adapter.make_identity(
        agent_id=agent_id,
        policy_ref=spec.ref,
    )
    engine = Engine(birkin_signing_key=sk, policy=spec, adapter=adapter)
    engine.start_session(identity)
    request = adapter.build_action_request(
        tool=tool, args=json.loads(args_json), justification="cli run"
    )
    receipt = engine.attempt_action(identity, request)
    if receipt.decision == "allow":
        engine.execute(identity, request, receipt)
    engine.checkpoint()
    engine.end_session(identity)
    engine.export_to_file(out, identity=identity)
    typer.echo(
        f"wrote {out}  decision={receipt.decision}  rule={receipt.rule}  "
        f"risk={receipt.risk_score}"
    )


if __name__ == "__main__":
    app()
