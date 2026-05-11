import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { ReceiptsModule } from './receipts/receipts.module.js';
import { AgentModule } from './agent/agent.module.js';
import { HealthController } from './health.controller.js';

@Module({
  imports: [ConfigModule.forRoot({ isGlobal: true }), ReceiptsModule, AgentModule],
  controllers: [HealthController],
})
export class AppModule {}
