import { TerminalSection } from "../components/terminal-section";

export default function McpPage() {
  return (
    <TerminalSection title="MCP Server Integration" id="mcp">
      <div className="text-sm space-y-4">
        <p className="text-[#888]">
          Configure and manage Model Context Protocol servers for your sandboxed agents.
        </p>
        <div className="border border-[#333] bg-[#111] p-4 text-center">
          <p className="text-[#666] text-xs">Coming soon</p>
        </div>
      </div>
    </TerminalSection>
  );
}
