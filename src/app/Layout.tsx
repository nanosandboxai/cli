import { Outlet } from "react-router";
import { TerminalHeader } from "./components/terminal-header";

const navItems = [
  { path: "/", label: "home" },
  { path: "/mcp", label: "mcp" },
  { path: "/skill", label: "skill" },
  { path: "/agents", label: "agents" },
  { path: "/docs", label: "docs" },
];

export default function Layout() {
  return (
    <div className="min-h-screen bg-[#0a0a0a] text-white">
      <TerminalHeader navItems={navItems} />

      <main className="container mx-auto px-4 py-6 max-w-7xl">
        <Outlet />
      </main>

      {/* Bottom Status Bar */}
      <div className="fixed bottom-0 left-0 right-0 border-t border-[#444] bg-black">
        <div className="px-4 py-1 flex items-center gap-4 font-mono text-xs">
          <span className="text-[#ff6b6b]">$</span>
          <span className="text-[#888]">nanosb --help</span>
          <div className="flex-1"></div>
          <span className="text-[#888]">[Ctrl+C] Exit</span>
          <span className="text-[#888]">[↑↓] Navigate</span>
          <span className="text-[#888]">[Enter] Select</span>
        </div>
      </div>
    </div>
  );
}
