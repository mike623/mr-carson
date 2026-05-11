import { Injectable } from '@nestjs/common';
import { buildAgent } from '@mr-carson/ai-tools';
import { migrate, seedCategories } from '@mr-carson/database';

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
    const agent = buildAgent(userId);
    const result = await agent.generate(message, { maxSteps: 6 });
    return result.text ?? '';
  }
}
