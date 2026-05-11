import { Injectable, Logger, NotFoundException } from '@nestjs/common';
import { migrate, pendingRepo, seedCategories } from '@mr-carson/database';
import { commitConfirmed, processReceipt } from '@mr-carson/ai-tools';
import type { Expense } from '@mr-carson/shared-types';

@Injectable()
export class ReceiptsService {
  private readonly logger = new Logger(ReceiptsService.name);
  private bootstrapped = false;

  private async ensureSchema(): Promise<void> {
    if (this.bootstrapped) return;
    await migrate();
    await seedCategories();
    this.bootstrapped = true;
  }

  async ingest(input: {
    userId: string;
    chatId: string;
    filePath: string;
  }): Promise<{ pendingId: string; expense: Expense }> {
    await this.ensureSchema();
    const pendingId = await pendingRepo.createPending({
      userId: input.userId,
      chatId: input.chatId,
      filePath: input.filePath,
    });
    try {
      const expense = await processReceipt({ pendingId, filePath: input.filePath });
      return { pendingId, expense };
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      this.logger.error(`processReceipt failed: ${msg}`);
      await pendingRepo.setPendingStatus(pendingId, 'FAILED', msg);
      throw err;
    }
  }

  async confirm(pendingId: string): Promise<{ id: string }> {
    await this.ensureSchema();
    const pending = await pendingRepo.getPending(pendingId);
    if (!pending) throw new NotFoundException(`pending ${pendingId} not found`);
    if (!pending.extracted) {
      throw new NotFoundException(`pending ${pendingId} has no extracted expense`);
    }
    if (pending.status === 'INSERTED') {
      // Idempotent: re-confirming a saved receipt should not duplicate.
      return { id: pendingId };
    }
    return commitConfirmed({
      pendingId,
      userId: pending.userId,
      expense: pending.extracted,
      sourceFile: pending.filePath,
    });
  }

  async reject(pendingId: string): Promise<void> {
    await this.ensureSchema();
    await pendingRepo.setPendingStatus(pendingId, 'REJECTED');
  }

  async getPending(pendingId: string) {
    await this.ensureSchema();
    return pendingRepo.getPending(pendingId);
  }
}
