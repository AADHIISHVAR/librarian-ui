import { ConfigService } from '@config/env.config';
import { Logger } from '@config/logger.config';
import { PrismaClient } from '@prisma/client';
import fs from 'fs';
import path from 'path';

export class Query<T> {
  where?: T;
  sort?: 'asc' | 'desc';
  page?: number;
  offset?: number;
}

export class PrismaRepository extends PrismaClient {
  constructor(private readonly configService: ConfigService) {
    const dbConfig = configService.get<any>('DATABASE');
    const URI = dbConfig?.CONNECTION?.URI || process.env.DATABASE_URL;
    const logger = new Logger('PrismaRepository');
    
    logger.info(`Prisma attempting connection...`);
    logger.info(`DATABASE_PROVIDER: ${process.env.DATABASE_PROVIDER}`);
    logger.info(`Target URI: ${URI}`);

    let finalUri = URI;
    if (URI && URI.startsWith('file:')) {
      const filePath = URI.replace('file:', '');
      // Ensure we have a clean path without extra slashes
      const cleanPath = filePath.replace(/^\/+/, '/'); 
      const fullPath = path.isAbsolute(cleanPath) ? cleanPath : path.join(process.cwd(), cleanPath);
      finalUri = `file:${fullPath}`;
      logger.info(`Source URI: ${URI}`);
      logger.info(`Final Connection URL: ${finalUri}`);
      
      if (fs.existsSync(fullPath)) {
        const stats = fs.statSync(fullPath);
        logger.info(`Database file verified at: ${fullPath} (${stats.size} bytes)`);
      } else {
        logger.error(`CRITICAL: Database file missing at: ${fullPath}`);
      }
    }
    
    super({
      datasources: {
        db: {
          url: finalUri,
        },
      },
    });
  }

  private readonly logger = new Logger('PrismaRepository');

  public async onModuleInit() {
    await this.$connect();
    this.logger.info('Repository:Prisma - ON');
  }

  public async onModuleDestroy() {
    await this.$disconnect();
    this.logger.warn('Repository:Prisma - OFF');
  }
}
