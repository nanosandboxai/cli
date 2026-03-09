import { useState, useEffect } from "react";

export function TerminalHeader() {
  const [cpu, setCpu] = useState(23);
  const [memory, setMemory] = useState(41);
  const [time, setTime] = useState(new Date());

  useEffect(() => {
    // Update CPU and memory every 2 seconds
    const systemInterval = setInterval(() => {
      setCpu(Math.floor(Math.random() * 60) + 15); // 15-75%
      setMemory(Math.floor(Math.random() * 40) + 30); // 30-70%
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

  const formatTime = (date: Date) => {
    return date.toLocaleTimeString('en-US', { 
      hour: '2-digit', 
      minute: '2-digit',
      second: '2-digit',
      hour12: true 
    });
  };

  return (
    <header className="border-b border-[#444] bg-black">
      <div className="px-4 py-2 flex items-center justify-between font-mono text-sm">
        <div className="flex items-center gap-2">
          <span className="text-[#888]">nanosandbox@terminal:~</span>
          <span className="inline-block w-2 h-4 bg-white animate-pulse"></span>
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