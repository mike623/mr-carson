import { Module } from '@nestjs/common';
import { AgentController } from './agent.controller.js';
import { AgentService } from './agent.service.js';

@Module({
  controllers: [AgentController],
  providers: [AgentService],
})
export class AgentModule {}
