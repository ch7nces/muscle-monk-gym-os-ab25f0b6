import { createFileRoute } from "@tanstack/react-router";
import { ArrowUpRight, Dumbbell, FileCode2 } from "lucide-react";
import { Button } from "@/components/ui/button";
import gymPhoto from "@/assets/hero-gym.jpg";

export const Route = createFileRoute("/")({
  head: () => ({
    meta: [
      { title: "Muscle Monk Gym OS — Import status" },
      { name: "description", content: "Muscle Monk Gym OS source import. The source repository contains the gym theme and data definitions; application pages are not included." },
      { property: "og:title", content: "Muscle Monk Gym OS — Import status" },
      { property: "og:description", content: "The available gym assets have been preserved. Complete application source is needed to finish the import." },
      { property: "og:type", content: "website" },
      { name: "twitter:card", content: "summary_large_image" },
    ],
  }),
  component: Index,
});

function Index() {
  return (
    <main className="min-h-screen bg-background">
      <header className="mx-auto flex max-w-5xl items-center gap-3 px-6 py-6">
        <Dumbbell className="size-7 text-primary" aria-hidden="true" />
        <span className="font-display text-2xl">MUSCLE MONK</span>
        <span className="ml-auto text-xs text-muted-foreground">GYM OS</span>
      </header>
      <div className="mx-auto max-w-5xl px-6">
        <img src={gymPhoto} alt="Gym equipment from the Muscle Monk source repository" className="aspect-[21/8] w-full object-cover" />
        <section className="max-w-2xl py-10 md:py-14" aria-labelledby="import-title">
          <div className="mb-5 flex items-center gap-2 text-sm text-warning"><FileCode2 className="size-4" aria-hidden="true" />Incomplete source</div>
          <h1 id="import-title" className="font-display text-4xl leading-tight md:text-5xl">Muscle Monk Gym OS</h1>
          <p className="mt-5 text-lg leading-relaxed text-muted-foreground">The repository includes the gym’s theme, photo, and data definitions, but its home page is blank. The gym application pages are not included.</p>
          <p className="mt-4 leading-relaxed text-muted-foreground">To finish the import, attach a ZIP of the complete application or share the repository that contains it in the chat.</p>
          <Button asChild variant="outline" className="mt-7"><a href="https://github.com/ch7nces/muscle-monk-gym-os" target="_blank" rel="noopener noreferrer">View source repository <ArrowUpRight aria-hidden="true" /></a></Button>
          <div className="mt-10 flex flex-wrap gap-x-8 gap-y-3 border-t border-border pt-6 text-sm text-muted-foreground"><span>Theme preserved</span><span>Gym photo imported</span><span>Cloud connected</span></div>
        </section>
      </div>
    </main>
  );
}
