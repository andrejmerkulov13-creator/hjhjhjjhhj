export class HttpError extends Error { constructor(status, message, code='ERROR'){ super(message); this.status=status; this.code=code; } }
export const asyncRoute = fn => (req,res,next) => Promise.resolve(fn(req,res,next)).catch(next);
