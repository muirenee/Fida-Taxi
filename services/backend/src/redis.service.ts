import { Injectable, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { createClient, RedisClientType } from 'redis';

@Injectable()
export class RedisService implements OnModuleInit, OnModuleDestroy {
  private readonly client: RedisClientType = createClient({
    socket: {
      host: process.env.REDIS_HOST ?? 'redis',
      port: Number(process.env.REDIS_PORT ?? 6379),
    },
    password: process.env.REDIS_PASSWORD,
  });

  async onModuleInit(): Promise<void> {
    this.client.on('error', (error) => {
      console.error('[redis]', error);
    });
    await this.client.connect();
  }

  async onModuleDestroy(): Promise<void> {
    if (this.client.isOpen) await this.client.quit();
  }

  async setEx(key: string, seconds: number, value: string): Promise<void> {
    await this.client.setEx(key, seconds, value);
  }

  async get(key: string): Promise<string | null> {
    return this.client.get(key);
  }

  async del(key: string): Promise<void> {
    await this.client.del(key);
  }

  async geoAdd(
    key: string,
    member: string,
    longitude: number,
    latitude: number,
  ): Promise<void> {
    await this.client.geoAdd(key, { member, longitude, latitude });
  }

  async geoRemove(key: string, member: string): Promise<void> {
    await this.client.zRem(key, member);
  }

  async geoPosition(
    key: string,
    member: string,
  ): Promise<{ latitude: number; longitude: number } | null> {
    const positions = await this.client.geoPos(key, member);
    const position = positions[0];
    if (!position) return null;

    return {
      latitude: Number(position.latitude),
      longitude: Number(position.longitude),
    };
  }

  async nearbyDriverIds(
    longitude: number,
    latitude: number,
    radiusKm: number,
    count: number,
  ): Promise<string[]> {
    return this.client.geoSearch(
      'drivers:locations',
      { longitude, latitude },
      { radius: radiusKm, unit: 'km' },
      { COUNT: count, SORT: 'ASC' },
    );
  }

  async acquireLock(key: string, token: string, ttlMs: number): Promise<boolean> {
    const result = await this.client.set(key, token, { NX: true, PX: ttlMs });
    return result === 'OK';
  }

  async releaseLock(key: string, token: string): Promise<void> {
    const current = await this.client.get(key);
    if (current === token) await this.client.del(key);
  }
}
