import { closeConnection } from '../client.js';
import { migrate } from '../migrate.js';

await migrate();
console.log('migrate: schema applied');
await closeConnection();
