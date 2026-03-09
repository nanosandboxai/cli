import { TerminalSection } from "../components/terminal-section";

export default function SkillPage() {
  return (
    <TerminalSection title="Skills" id="skill">
      <div className="text-sm space-y-4">
        <p className="text-[#888]">
          Extend agent capabilities with composable skills.
        </p>
        <div className="border border-[#333] bg-[#111] p-4 text-center">
          <p className="text-[#666] text-xs">Coming soon</p>
        </div>
      </div>
    </TerminalSection>
  );
}
