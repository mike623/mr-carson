import { Body, Controller, NotFoundException, Param, Post, Get } from '@nestjs/common';
import { z } from 'zod';
import { ReceiptsService } from './receipts.service.js';

const IngestBody = z.object({
  userId: z.string().min(1),
  chatId: z.string().min(1),
  filePath: z.string().min(1),
});

@Controller('receipts')
export class ReceiptsController {
  constructor(private readonly receipts: ReceiptsService) {}

  @Post('ingest')
  async ingest(@Body() body: unknown) {
    const parsed = IngestBody.parse(body);
    return this.receipts.ingest(parsed);
  }

  @Get(':id')
  async getOne(@Param('id') id: string) {
    const pending = await this.receipts.getPending(id);
    if (!pending) throw new NotFoundException();
    return pending;
  }

  @Post(':id/confirm')
  async confirm(@Param('id') id: string) {
    return this.receipts.confirm(id);
  }

  @Post(':id/reject')
  async reject(@Param('id') id: string) {
    await this.receipts.reject(id);
    return { ok: true };
  }
}
