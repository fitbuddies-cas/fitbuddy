import asyncio
import sys
from claude_agent_sdk import (
    query, ClaudeAgentOptions,
    tool, create_sdk_mcp_server,
    AssistantMessage, TextBlock, ToolUseBlock, ResultMessage,
)

# Windows-Konsole auf UTF-8 umstellen (siehe first_agent.py)
sys.stdout.reconfigure(encoding="utf-8")


# ── Schritt 1: Eigenes Tool definieren ──────────────────────────
# @tool(name, beschreibung, input-schema)
#   name         → für die Engine (wird Teil von mcp__weather__celsius_to_f)
#   beschreibung → für das MODELL: danach entscheidet es, ob es das Tool aufruft
#   schema       → Vertrag: welche Parameter, welche Typen

@tool("Deutsche_Rechtschreibung", "Prüft alle Dokumente die auf Deutsch geschrieben sind", {"text": string})
async def c2f(args):
    # args ist ein dict gemäss Schema: {"c": 25.0}
    result = args["c"] * 9 / 5 + 32
    # Rückgabe IMMER in diesem Format — das Ergebnis geht als
    # Nachricht zurück in den Agent-Loop:
    return {"content": [{"type": "text", "text": str(result)}]}


# ── Schritt 2: Tool in einen In-Process-MCP-Server packen ──────
weather = create_sdk_mcp_server(name="weather", version="1.0.0", tools=[c2f])


# ── Schritt 3: Server anschliessen + Tool erlauben ─────────────
opts = ClaudeAgentOptions(
    model="claude-sonnet-4-6",
    mcp_servers={"weather": weather},
    #                 └── dieser Schlüssel landet im Tool-Namen:
    allowed_tools=["mcp__weather__celsius_to_f"],
    #               mcp__<schlüssel>__<tool-name>
    max_turns=4,
    max_budget_usd=0.20,
)


# ── Schritt 4: Aufgabe stellen, die das Tool provoziert ────────
async def main():
    async for msg in query(
        prompt="Wie viel Fahrenheit sind 1 Grad Celsius? Nutze dein Tool.",
        options=opts,
    ):
        if isinstance(msg, AssistantMessage):
            for block in msg.content:
                if isinstance(block, ToolUseBlock):
                    # Hier SEHT ihr den Tool-Aufruf im Stream:
                    print(f">>> TOOL-CALL: {block.name}  Input: {block.input}")
                elif isinstance(block, TextBlock):
                    print(block.text)
        elif isinstance(msg, ResultMessage):
            print(f"\n--- Turns: {msg.num_turns} · Kosten: ${msg.total_cost_usd:.4f} ---")

asyncio.run(main())
