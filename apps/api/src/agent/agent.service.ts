import { Injectable } from '@nestjs/common';
import { runAgent } from '@mr-carson/ai-tools';
import { chatSessionsRepo, migrate, seedCategories } from '@mr-carson/database';

export interface AskResult {
  reply: string;
  attachments: string[];
}

// Cap how many receipt images we send back per question — keeps the bot
// from spamming the chat when a broad query (e.g. "this month") matches
// many receipts.
const MAX_ATTACHMENTS = 5;

@Injectable()
export class AgentService {
  private bootstrapped = false;

  private async ensureSchema(): Promise<void> {
    if (this.bootstrapped) return;
    await migrate();
    await seedCategories();
    this.bootstrapped = true;
  }

  async ask(userId: string, message: string): Promise<AskResult> {
    await this.ensureSchema();
    const threadId = await chatSessionsRepo.getOrCreateActiveThread(userId);
    const seen = new Set<string>();
    const collector = { add: (p: string) => seen.add(p) };
    const reply = await runAgent(userId, threadId, message, collector);
    return {
      reply,
      attachments: Array.from(seen).slice(0, MAX_ATTACHMENTS),
    };
  }

  async newSession(userId: string): Promise<{ threadId: string }> {
    await this.ensureSchema();
    const threadId = await chatSessionsRepo.rotateActiveThread(userId);
    return { threadId };
  }
}
