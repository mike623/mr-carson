import { Body, Controller, Post } from '@nestjs/common';
import { z } from 'zod';
import { AgentService } from './agent.service.js';

const AskBody = z.object({
  userId: z.string().min(1),
  message: z.string().min(1),
});

@Controller('agent')
export class AgentController {
  constructor(private readonly agent: AgentService) {}

  @Post('ask')
  async ask(@Body() body: unknown) {
    const parsed = AskBody.parse(body);
    const reply = await this.agent.ask(parsed.userId, parsed.message);
    return { reply };
  }
}
