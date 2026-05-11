import { closeConnection } from '../client.js';
import { migrate } from '../migrate.js';
import { seedCategories } from '../seed.js';

await migrate();
await seedCategories();
console.log('seed: default categories applied');
await closeConnection();
