import { useState } from "react";
import { CodeBlock } from "./code-block";

export function InstallTabs() {
  const [activeTab, setActiveTab] = useState<"bash" | "powershell">("bash");

  const bashInstall = `curl -fsSL https://install.nanosandbox.dev/install.sh | sh`;
  const powershellInstall = `# PowerShell installation coming soon
# Follow updates at https://github.com/anthropics/nanosandbox`;

  return (
    <div>
      <div className="flex gap-4 mb-3 text-sm">
        <button
          onClick={() => setActiveTab("bash")}
          className={`transition-colors ${
            activeTab === "bash"
              ? "text-[#ff6b6b]"
              : "text-[#888] hover:text-white"
          }`}
        >
          {activeTab === "bash" ? "▸" : " "} Shell (Bash/Zsh)
        </button>
        <button
          onClick={() => setActiveTab("powershell")}
          className={`transition-colors ${
            activeTab === "powershell"
              ? "text-[#ff6b6b]"
              : "text-[#888] hover:text-white"
          }`}
        >
          {activeTab === "powershell" ? "▸" : " "} PowerShell
        </button>
      </div>

      {activeTab === "bash" && <CodeBlock code={bashInstall} />}
      
      {activeTab === "powershell" && (
        <>
          <div className="mb-3 border border-[#664400] bg-[#110800] p-3 text-sm">
            <p className="text-[#ff9933] mb-1">[!] In Development</p>
            <p className="text-[#888]">PowerShell installation script is currently being prepared.</p>
          </div>
          <CodeBlock code={powershellInstall} language="powershell" />
        </>
      )}
    </div>
  );
}