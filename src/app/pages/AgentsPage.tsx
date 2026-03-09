import { TerminalSection } from "../components/terminal-section";

export default function AgentsPage() {
  return (
    <TerminalSection title="Supported Agents" id="agents">
      <div className="text-sm space-y-4">
        <p className="text-[#888]">
          Run AI coding agents in isolated VM sandboxes.
        </p>
        <div className="grid md:grid-cols-3 gap-4 mt-4">
          {["Claude Code", "Goose", "Codex", "Cursor", "OpenCode"].map((agent) => (
            <div key={agent} className="border border-[#333] bg-[#111] p-3">
              <span className="text-[#ff6b6b]">▸</span> <span className="text-white">{agent}</span>
            </div>
          ))}
        </div>
        <div className="border border-[#333] bg-[#111] p-4 text-center">
          <p className="text-[#666] text-xs">Detailed agent documentation coming soon</p>
        </div>
      </div>
    </TerminalSection>
  );
}
