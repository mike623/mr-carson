import { Injectable } from '@nestjs/common';
import { buildAgent, type ChartSink } from '@mr-carson/ai-tools';
import { migrate, seedCategories } from '@mr-carson/database';

export interface AskResult {
  reply: string;
  imageBase64?: string;
}

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
    const chartSink: ChartSink = {};
    const agent = buildAgent(userId, { chartSink });
    const result = await agent.generate(message, { maxSteps: 6 });
    return {
      reply: result.text ?? '',
      ...(chartSink.imageBase64 ? { imageBase64: chartSink.imageBase64 } : {}),
    };
  }
}
