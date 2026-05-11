import { Controller, Get } from '@nestjs/common';

@Controller('health')
export class HealthController {
  @Get()
  ping() {
    return { ok: true, name: 'mr-carson-api', ts: new Date().toISOString() };
  }
}
