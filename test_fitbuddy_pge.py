"""Praxis-Test 2 (Tag 2): Mini Planner->Generator->Evaluator.
Kleine, schnelle Aufgabe damit der Lauf < 1 Min und < $0.50 bleibt."""

import asyncio, sys
from claude_agent_sdk import query, ClaudeAgentOptions, AssistantMessage, TextBlock
sys.stdout.reconfigure(encoding="utf-8")

def role_opts(system, tools=None, budget=2.50):
    return ClaudeAgentOptions(
        model="claude-sonnet-4-6", system_prompt=system,
        allowed_tools=tools or [], max_turns=10, max_budget_usd=budget,
    )

planner_o   = role_opts("Du bist Planner. Zerlege die Aufgabe in eine knappe Spec: Inputs, Outputs, Edge Cases. Kein Code.")
generator_o = role_opts("Du bist Generator. Setze die Spec exakt um. NUR Code. Du hast Schreibrechte auf '/home/ro/CAS/fitbuddy/design/`.", budget=1.30, tools="Write")
evaluator_o = role_opts("Du bist Evaluator. Prüfe den Code gegen die Spec. Erste Zeile NUR 'PASS' oder 'FAIL: <Grund>'.")

async def run(opts, prompt):
    out = []
    async for msg in query(prompt=prompt, options=opts):
        if isinstance(msg, AssistantMessage):
            for b in msg.content:
                if isinstance(b, TextBlock):
                    out.append(b.text)
    return "\n".join(out)

async def main():
    task = "Erstelle eine HTML Seite mit den wichtigsten 2 Views der iOS App"
    print("=== PLANNER ===")
    plan = await run(planner_o, f"Aufgabe: {task}")
    print(plan[:400])
    for rnd in range(1, 3):
        print(f"\n=== GENERATOR (Runde {rnd}) ===")
        code = await run(generator_o, f"Spec:\n{plan}")
        print(code[:400])
        print(f"\n=== EVALUATOR (Runde {rnd}) ===")
        verdict = await run(evaluator_o, f"Spec:\n{plan}\n\nCode:\n{code}")
        print(verdict[:300])
        if verdict.strip().upper().startswith("PASS"):
            print(f"\n*** PASS in Runde {rnd} ***")
            return
        plan += f"\n\nEvaluator-Feedback: {verdict}"
    print("\n*** kein PASS nach 2 Runden -> Mensch entscheidet ***")

asyncio.run(main())
