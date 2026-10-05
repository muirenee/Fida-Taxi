import {
  BadGatewayException,
  Injectable,
  ServiceUnavailableException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import {
  PlaceSearchDto,
  ReverseGeocodeDto,
  RoutePreviewDto,
} from './maps.dto';

interface NominatimPlace {
  place_id?: number | string;
  display_name?: string;
  lat?: string;
  lon?: string;
}

interface OsrmRouteResponse {
  code?: string;
  routes?: Array<{
    distance?: number;
    duration?: number;
    geometry?: {
      type?: string;
      coordinates?: Array<[number, number]>;
    };
  }>;
}

@Injectable()
export class MapsService {
  constructor(private readonly config: ConfigService) {}

  async search(dto: PlaceSearchDto) {
    const url = this.providerUrl('GEOCODING_BASE_URL', 'https://nominatim.openstreetmap.org', 'search');
    url.searchParams.set('format', 'jsonv2');
    url.searchParams.set('addressdetails', '1');
    url.searchParams.set('limit', '7');
    url.searchParams.set('q', dto.q.trim());

    const countryCodes = this.config.get<string>('MAPS_COUNTRY_CODES')?.trim() || 'rw';
    if (countryCodes) url.searchParams.set('countrycodes', countryCodes);

    if (dto.latitude != null && dto.longitude != null) {
      const delta = 0.35;
      url.searchParams.set(
        'viewbox',
        [
          dto.longitude - delta,
          dto.latitude + delta,
          dto.longitude + delta,
          dto.latitude - delta,
        ].join(','),
      );
      url.searchParams.set('bounded', '0');
    }

    const payload = await this.fetchJson<unknown>(url);
    if (!Array.isArray(payload)) {
      throw new BadGatewayException('Geocoding provider returned an invalid response');
    }

    return {
      places: payload
        .map((value) => this.normalizePlace(value))
        .filter((value): value is NonNullable<typeof value> => value != null),
    };
  }

  async reverse(dto: ReverseGeocodeDto) {
    const url = this.providerUrl('GEOCODING_BASE_URL', 'https://nominatim.openstreetmap.org', 'reverse');
    url.searchParams.set('format', 'jsonv2');
    url.searchParams.set('addressdetails', '1');
    url.searchParams.set('zoom', '18');
    url.searchParams.set('lat', String(dto.latitude));
    url.searchParams.set('lon', String(dto.longitude));

    const payload = await this.fetchJson<unknown>(url);
    const place = this.normalizePlace(payload);
    if (!place) {
      return {
        place: {
          id: `coordinate:${dto.latitude},${dto.longitude}`,
          label: `${dto.latitude.toFixed(5)}, ${dto.longitude.toFixed(5)}`,
          latitude: dto.latitude,
          longitude: dto.longitude,
        },
      };
    }

    return { place };
  }

  async route(dto: RoutePreviewDto) {
    const path = `route/v1/driving/${dto.pickup_lng},${dto.pickup_lat};${dto.dropoff_lng},${dto.dropoff_lat}`;
    const url = this.providerUrl('ROUTING_BASE_URL', 'https://router.project-osrm.org', path);
    url.searchParams.set('overview', 'full');
    url.searchParams.set('geometries', 'geojson');
    url.searchParams.set('steps', 'false');
    url.searchParams.set('alternatives', 'false');

    const payload = await this.fetchJson<OsrmRouteResponse>(url);
    const route = payload.routes?.[0];
    const coordinates = route?.geometry?.coordinates;

    if (
      payload.code !== 'Ok' ||
      route == null ||
      !Array.isArray(coordinates) ||
      coordinates.length < 2
    ) {
      throw new BadGatewayException('Routing provider could not build a route');
    }

    return {
      distance_meters: Math.round(Number(route.distance ?? 0)),
      duration_seconds: Math.round(Number(route.duration ?? 0)),
      coordinates: coordinates
        .filter(
          (coordinate): coordinate is [number, number] =>
            Array.isArray(coordinate) &&
            coordinate.length >= 2 &&
            Number.isFinite(coordinate[0]) &&
            Number.isFinite(coordinate[1]),
        )
        .map(([longitude, latitude]) => ({ latitude, longitude })),
    };
  }

  private normalizePlace(value: unknown) {
    if (value == null || typeof value !== 'object') return null;
    const raw = value as NominatimPlace;
    const latitude = Number(raw.lat);
    const longitude = Number(raw.lon);
    const label = raw.display_name?.trim();

    if (!label || !Number.isFinite(latitude) || !Number.isFinite(longitude)) {
      return null;
    }

    return {
      id: String(raw.place_id ?? `${latitude},${longitude}`),
      label,
      latitude,
      longitude,
    };
  }

  private providerUrl(envKey: string, fallbackBase: string, path: string): URL {
    const configured = this.config.get<string>(envKey)?.trim() || fallbackBase;
    const base = `${configured.replace(/\/+$/, '')}/`;
    return new URL(path.replace(/^\/+/, ''), base);
  }

  private async fetchJson<T>(url: URL): Promise<T> {
    const userAgent =
      this.config.get<string>('MAPS_USER_AGENT')?.trim() ||
      'FidaTaxi/0.1 (+https://fidalix.com)';

    try {
      const response = await fetch(url, {
        headers: {
          accept: 'application/json',
          'user-agent': userAgent,
        },
        signal: AbortSignal.timeout(8000),
      });

      if (!response.ok) {
        throw new BadGatewayException(
          `Map provider returned HTTP ${response.status}`,
        );
      }

      return (await response.json()) as T;
    } catch (error) {
      if (error instanceof BadGatewayException) throw error;
      throw new ServiceUnavailableException(
        'Map service is temporarily unavailable',
      );
    }
  }
}
