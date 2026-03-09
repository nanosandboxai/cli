import { useState, useEffect } from "react";
import { Link, useLocation } from "react-router";

interface NavItem {
  path: string;
  label: string;
}

interface TerminalHeaderProps {
  navItems?: NavItem[];
}

export function TerminalHeader({ navItems = [] }: TerminalHeaderProps) {
  const [cpu, setCpu] = useState(23);
  const [memory, setMemory] = useState(41);
  const [time, setTime] = useState(new Date());
  const [typedCount, setTypedCount] = useState(0);
  const location = useLocation();

  // Total characters across all nav labels (for typing animation)
  const allText = navItems.map((item) => item.label).join("");
  const totalChars = allText.length;

  useEffect(() => {
    // Update CPU and memory every 2 seconds
    const systemInterval = setInterval(() => {
      setCpu(Math.floor(Math.random() * 60) + 15);
      setMemory(Math.floor(Math.random() * 40) + 30);
    }, 2000);

    // Update time every second
    const timeInterval = setInterval(() => {
      setTime(new Date());
    }, 1000);

    return () => {
      clearInterval(systemInterval);
      clearInterval(timeInterval);
    };
  }, []);

  // Typing animation: reveal characters one by one
  useEffect(() => {
    if (totalChars === 0) return;
    if (typedCount >= totalChars) return;

    const delay = typedCount === 0 ? 400 : 50; // initial pause, then fast typing
    const timer = setTimeout(() => {
      setTypedCount((c) => c + 1);
    }, delay);

    return () => clearTimeout(timer);
  }, [typedCount, totalChars]);

  const formatTime = (date: Date) => {
    return date.toLocaleTimeString("en-US", {
      hour: "2-digit",
      minute: "2-digit",
      second: "2-digit",
      hour12: true,
    });
  };

  // Calculate how many characters each nav item should show
  const getVisibleLabel = (index: number) => {
    let charsBefore = 0;
    for (let i = 0; i < index; i++) {
      charsBefore += navItems[i].label.length;
    }
    const charsAvailable = typedCount - charsBefore;
    if (charsAvailable <= 0) return "";
    return navItems[index].label.slice(0, charsAvailable);
  };

  const isTypingDone = typedCount >= totalChars;

  // Cursor position: which nav item is currently being typed
  const getCursorItemIndex = () => {
    let charsSoFar = 0;
    for (let i = 0; i < navItems.length; i++) {
      charsSoFar += navItems[i].label.length;
      if (typedCount < charsSoFar) return i;
    }
    return -1; // done typing all items
  };
  const cursorItemIndex = getCursorItemIndex();

  return (
    <header className="border-b border-[#444] bg-black">
      <div className="px-4 py-2 flex items-center justify-between font-mono text-sm">
        <div className="flex items-center gap-0">
          <span className="text-[#888] mr-1">nanosandbox@terminal:~</span>

          {/* Cursor sits before nav if nothing typed yet */}
          {navItems.length > 0 && cursorItemIndex === 0 && typedCount === 0 && (
            <span className="inline-block w-2 h-4 bg-white animate-pulse mr-1"></span>
          )}

          {/* Nav items rendered inline */}
          {navItems.map((item, index) => {
            const visibleLabel = getVisibleLabel(index);
            if (visibleLabel.length === 0 && cursorItemIndex !== index) return null;

            const isFullyTyped = visibleLabel === item.label;
            const isActive = location.pathname === item.path;
            const showCursor = cursorItemIndex === index && typedCount > 0;

            return (
              <span key={item.path} className="inline-flex items-center">
                {isFullyTyped ? (
                  <Link
                    to={item.path}
                    className={`px-3 py-1 border-r border-[#444] transition-colors ${
                      isActive
                        ? "text-[#ff6b6b] bg-[#1a1a1a]"
                        : "text-[#888] hover:text-white hover:bg-[#111]"
                    }`}
                  >
                    {item.label}
                  </Link>
                ) : (
                  <span className="px-3 py-1 border-r border-[#444] text-[#888]">
                    {visibleLabel}
                  </span>
                )}
                {showCursor && (
                  <span className="inline-block w-2 h-4 bg-white animate-pulse"></span>
                )}
              </span>
            );
          })}

          {/* Cursor after all items are typed */}
          {isTypingDone && navItems.length > 0 && (
            <span className="inline-block w-2 h-4 bg-white animate-pulse ml-1"></span>
          )}

          {/* Cursor when no nav items */}
          {navItems.length === 0 && (
            <span className="inline-block w-2 h-4 bg-white animate-pulse ml-1"></span>
          )}
        </div>

        <div className="flex items-center gap-6 text-[#888]">
          <span>CPU: {cpu}%</span>
          <span>MEM: {memory}%</span>
          <span className="text-white">{formatTime(time)}</span>
        </div>
      </div>
    </header>
  );
}
