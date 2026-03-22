import { handlers } from '@/lib/auth-options'

/**
 * NextAuth v5 catch-all route handler.
 * All /api/auth/* requests are handled by the NextAuth core.
 */
export const { GET, POST } = handlers
