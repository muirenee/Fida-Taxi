export const rideStatuses = [
  'created',
  'matching',
  'accepted',
  'en_route',
  'arrived',
  'picked_up',
  'completed',
  'cancelled',
] as const;

export type RideStatus = (typeof rideStatuses)[number];
