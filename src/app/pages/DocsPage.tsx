import { TerminalSection } from "../components/terminal-section";

export default function DocsPage() {
  return (
    <TerminalSection title="Documentation" id="docs">
      <div className="text-sm space-y-4">
        <p className="text-[#888]">
          Complete reference for the nanosb CLI and SDK.
        </p>
        <div className="border border-[#333] bg-[#111] p-4 text-center">
          <p className="text-[#666] text-xs">Coming soon</p>
        </div>
      </div>
    </TerminalSection>
  );
}
