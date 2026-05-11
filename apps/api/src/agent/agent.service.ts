import { Injectable } from '@nestjs/common';
import { runAgent } from '@mr-carson/ai-tools';
import { chatSessionsRepo, migrate, seedCategories } from '@mr-carson/database';

@Injectable()
export class AgentService {
  private bootstrapped = false;

  private async ensureSchema(): Promise<void> {
    if (this.bootstrapped) return;
    await migrate();
    await seedCategories();
    this.bootstrapped = true;
  }

  async ask(userId: string, message: string): Promise<string> {
    await this.ensureSchema();
    const threadId = await chatSessionsRepo.getOrCreateActiveThread(userId);
    return runAgent(userId, threadId, message);
  }

  async newSession(userId: string): Promise<{ threadId: string }> {
    await this.ensureSchema();
    const threadId = await chatSessionsRepo.rotateActiveThread(userId);
    return { threadId };
  }
}
