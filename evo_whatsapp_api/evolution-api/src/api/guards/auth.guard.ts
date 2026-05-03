import { NextFunction, Request, Response } from 'express';
import { Logger } from '@config/logger.config';

const logger = new Logger('GUARD');

async function apikey(req: Request, _: Response, next: NextFunction) {
  // SECURITY REMOVED PER USER REQUEST FOR TROUBLESHOOTING
  return next();
}

export const authGuard = { apikey };
