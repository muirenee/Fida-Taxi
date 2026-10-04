export type AuthRole = 'rider' | 'driver';

export interface AuthPrincipal {
  user_id: string;
  role: AuthRole;
  driver_id?: string;
}
