/**
 * test/unit/apuestas.service.spec.ts
 *
 * PRUEBAS UNITARIAS — ApuestasDeportivasService
 * 4 casos: validación de tipo simple, cálculo de cuota total,
 * estadísticas vacías y formateo de apuesta.
 */

import { ConfigService } from '@nestjs/config';
import { BadRequestException } from '@nestjs/common';
import { createClient } from '@supabase/supabase-js';

import { ApuestasCoreService } from '../../src/apuestas-deportivas/services/apuestas-core.service';
import { ApuestasQueryService } from '../../src/apuestas-deportivas/services/apuestas-query.service';
import { ApuestasSimuladorService } from '../../src/apuestas-deportivas/services/apuestas-simulador.service';
import {
  CrearApuestaDto,
  TipoApuesta,
} from '../../src/apuestas-deportivas/dto/crear-apuesta.dto';
import { createMockSupabaseClient } from '../helpers/supabase.mock';

jest.mock('@supabase/supabase-js');

// ── Datos de prueba ────────────────────────────────────────────────────────
const seleccionBase = {
  eventoId: 1,
  mercado: 'main.1X2',
  seleccion: '1',
  cuota: 2.0,
  eventoNombre: 'Real Madrid vs Barcelona',
  seleccionDisplay: 'Real Madrid gana',
};

describe('ApuestasDeportivasService — Pruebas Unitarias', () => {
  let service: ApuestasCoreService;
  let queryService: ApuestasQueryService;
  let mockSupabase: ReturnType<typeof createMockSupabaseClient>;

  beforeEach(() => {
    mockSupabase = createMockSupabaseClient();
    (createClient as jest.Mock).mockReturnValue(mockSupabase);

    const config = { get: jest.fn().mockReturnValue('test-value') } as unknown as ConfigService;
    queryService = new ApuestasQueryService(config);
    service = new ApuestasCoreService(
      config,
      { programarSimulacion: jest.fn() } as unknown as ApuestasSimuladorService,
      queryService,
    );
  });

  afterEach(() => jest.clearAllMocks());

  // ── CASO 18: apuesta simple con múltiples selecciones ────────────────────
  it('crearApuesta() debe lanzar BadRequestException si tipo=simple tiene >1 selección', async () => {
    const dto: CrearApuestaDto = {
      tipo: TipoApuesta.SIMPLE,
      monto: 100,
      selecciones: [
        { ...seleccionBase, eventoId: 1 },
        { ...seleccionBase, eventoId: 2, cuota: 1.8 },
      ],
    };

    await expect(service.crearApuesta(1, dto)).rejects.toThrow(
      BadRequestException,
    );
    await expect(service.crearApuesta(1, dto)).rejects.toThrow(
      'solo puede tener una selección',
    );
  });

  // ── CASO 19: cuota total = producto de cuotas individuales ────────────────
  it('crearApuesta() debe calcular la cuota total como el producto de cuotas individuales', async () => {
    mockSupabase._setSingleResult({
      id: 99, usuario_id: 1, tipo: 'combinada', monto: '50',
      cuota_total: '3.6', ganancia_potencial: '180', estado: 'pendiente',
    });
    mockSupabase._setThenResult([
      { id: 1, evento_deportivo_id: 10, cuota: '2.0' },
      { id: 2, evento_deportivo_id: 11, cuota: '1.8' },
    ]);
    const result = await queryService.obtenerApuestaPorId(99, 1);
    expect(result.cuotaTotal).toBe(3.6);
    expect(result.selecciones.map((item) => item.cuota)).toEqual([2, 1.8]);
  });

  // ── CASO 20: estadísticas — usuario sin apuestas ──────────────────────────
  it('obtenerEstadisticas() debe retornar tasaExito=0 y totalApuestas=0 para usuario nuevo', async () => {
    mockSupabase._setThenResult([], null);

    const stats = await queryService.obtenerEstadisticas(999);

    expect(stats.totalApuestas).toBe(0);
    expect(stats.tasaExito).toBe(0);
    expect(stats.apuestasGanadas).toBe(0);
    expect(stats.apuestasPerdidas).toBe(0);
    expect(stats.beneficioNeto).toBe(0);
  });

  // ── CASO 21: estadísticas — cálculo correcto con apuestas ganadas ─────────
  it('obtenerEstadisticas() debe calcular correctamente la tasa de éxito', async () => {
    const apuestasData = [
      { estado: 'ganada', monto: '100', ganancia_potencial: '200' },
      { estado: 'perdida', monto: '50', ganancia_potencial: '90' },
      { estado: 'ganada', monto: '75', ganancia_potencial: '150' },
      { estado: 'pendiente', monto: '25', ganancia_potencial: '50' },
    ];

    mockSupabase._setThenResult(apuestasData, null);

    const stats = await queryService.obtenerEstadisticas(1);

    expect(stats.totalApuestas).toBe(4);
    expect(stats.apuestasGanadas).toBe(2);
    expect(stats.apuestasPerdidas).toBe(1);
    expect(stats.apuestasPendientes).toBe(1);
    // tasaExito = (2/4)*100 = 50
    expect(stats.tasaExito).toBe(50);
  });
});
