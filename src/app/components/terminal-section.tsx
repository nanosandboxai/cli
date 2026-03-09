import { ReactNode } from "react";

interface TerminalSectionProps {
  title: string;
  id?: string;
  children: ReactNode;
  className?: string;
}

export function TerminalSection({ title, id, children, className = "" }: TerminalSectionProps) {
  return (
    <section id={id} className={`font-mono ${className}`}>
      <div className="border border-[#444] bg-black">
        <div className="border-b border-[#444] px-3 py-1">
          <h2 className="text-[#ff6b6b] font-normal">┌─ {title}</h2>
        </div>
        <div className="p-4">
          {children}
        </div>
      </div>
    </section>
  );
}