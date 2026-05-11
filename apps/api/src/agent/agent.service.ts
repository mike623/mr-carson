import { Injectable } from '@nestjs/common';
import { buildAgent, type ChartSink } from '@mr-carson/ai-tools';
import { migrate, seedCategories } from '@mr-carson/database';

export interface AskResult {
  reply: string;
  attachments: string[];
  imageBase64?: string;
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
    const seen = new Set<string>();
    const collector = { add: (p: string) => seen.add(p) };
    const chartSink: ChartSink = {};
    const agent = buildAgent(userId, { attachments: collector, chartSink });
    const result = await agent.generate(message, { maxSteps: 6 });
    return {
      reply: result.text ?? '',
      attachments: Array.from(seen).slice(0, MAX_ATTACHMENTS),
      ...(chartSink.imageBase64 ? { imageBase64: chartSink.imageBase64 } : {}),
    };
  }
}
