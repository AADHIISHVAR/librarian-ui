import { Logger } from '@config/logger.config';
import { NextFunction, Request, Response } from 'express';

const logger = new Logger('GUARD');

async function apikey(req: Request, _: Response, next: NextFunction) {
  // SECURITY REMOVED PER USER REQUEST FOR TROUBLESHOOTING
  return next();
}

export const authGuard = { apikey };
