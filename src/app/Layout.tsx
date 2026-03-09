import { Outlet, Link, useLocation } from "react-router";
import { TerminalHeader } from "./components/terminal-header";

const navItems = [
  { path: "/", label: "home" },
  { path: "/mcp", label: "mcp" },
  { path: "/skill", label: "skill" },
  { path: "/agents", label: "agents" },
  { path: "/docs", label: "docs" },
];

export default function Layout() {
  const location = useLocation();

  return (
    <div className="min-h-screen bg-[#0a0a0a] text-white">
      <TerminalHeader />

      {/* Terminal Tab Nav */}
      <nav className="border-b border-[#444] bg-black">
        <div className="container mx-auto px-4 max-w-7xl flex items-center gap-0 font-mono text-sm">
          {navItems.map((item) => {
            const isActive = location.pathname === item.path;
            return (
              <Link
                key={item.path}
                to={item.path}
                className={`px-4 py-2 border-r border-[#444] transition-colors ${
                  isActive
                    ? "text-[#ff6b6b] bg-[#1a1a1a] border-b-2 border-b-[#ff6b6b]"
                    : "text-[#888] hover:text-white hover:bg-[#111]"
                }`}
              >
                {item.label}
              </Link>
            );
          })}
        </div>
      </nav>

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
