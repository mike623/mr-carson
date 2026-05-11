import { Body, Controller, Post } from '@nestjs/common';
import { z } from 'zod';
import { AgentService } from './agent.service.js';

const AskBody = z.object({
  userId: z.string().min(1),
  message: z.string().min(1),
});

const NewSessionBody = z.object({
  userId: z.string().min(1),
});

@Controller('agent')
export class AgentController {
  constructor(private readonly agent: AgentService) {}

  @Post('ask')
  async ask(@Body() body: unknown) {
    const parsed = AskBody.parse(body);
    return this.agent.ask(parsed.userId, parsed.message);
  }

  @Post('new')
  async newSession(@Body() body: unknown) {
    const parsed = NewSessionBody.parse(body);
    return this.agent.newSession(parsed.userId);
  }
}
