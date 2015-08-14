/*
 * Copyright (c) 2013-2015 Nathaniel Jones
 * Massachusetts Institute of Technology
 */

#include <optix.h>
#include <optixu/optixu_math_namespace.h>
#include "optix_shader_common.h"

using namespace optix;

/* OptiX variables */
rtDeclareVariable(Ray, ray, rtCurrentRay, );
rtDeclareVariable(float, t_hit, rtIntersectionDistance, );
rtDeclareVariable(PerRayData_point_cloud, prd, rtPayload, );

/* Attributes */
rtDeclareVariable(float3, geometric_normal, attribute geometric_normal, );
rtDeclareVariable(float3, shading_normal, attribute shading_normal, );

#ifdef AMBIENT_CELL
/* Context variables */
rtDeclareVariable(float3, cuorg, , ); /* bounding box minimum */
rtDeclareVariable(float, cell_size, , ); /* cell side dimension */
rtDeclareVariable(unsigned int, level, , ) = 0u;

rtDeclareVariable(unsigned int, ambient_ray_type, , );
rtDeclareVariable(rtObject, top_ambient, , );


RT_METHOD uint2 cell_hash(const float3& pos, const float3& dir)
{
	uint2 cell;
	float3 absdir = make_float3(fabsf(dir.x), fabsf(dir.y), fabsf(dir.z));
	if (absdir.x > absdir.y) {
		if (absdir.x > absdir.z)
			cell.x = dir.x > 0 ? 0 : 0x10000;
		else
			cell.x = dir.z > 0 ? 0x40000 : 0x50000;
	}
	else {
		if (absdir.y > absdir.z)
			cell.x = dir.y > 0 ? 0x20000 : 0x30000;
		else
			cell.x = dir.z > 0 ? 0x40000 : 0x50000;
	}
	float3 cell_index = (pos - cuorg) / cell_size;
	cell.x += ((unsigned int)cell_index.x) & 0xffff;
	cell.y = (((unsigned int)cell_index.y) << 16) + (((unsigned int)cell_index.z) & 0xffff);
	return cell;
}

RT_METHOD int occupied(const float3& pos, const float3& dir, const float3& world)
{
	float3 world_shading_normal = normalize(rtTransformNormal(RT_OBJECT_TO_WORLD, shading_normal));

	PerRayData_ambient ambient_prd;
	ambient_prd.result = make_float3(0.0f);
	ambient_prd.surface_normal = faceforward(world_shading_normal, -ray.direction, world);
	ambient_prd.ambient_depth = level;
	ambient_prd.wsum = 0.0f;
	ambient_prd.weight = 1.0f;
	for ( int i = level; i--; )
		ambient_prd.weight *= AVGREFL; // Compute weight as in makeambient() from ambient.c

#ifdef OLDAMB
	ambient_prd.state = prd.state; // TODO make available here
#endif
#ifdef DAYSIM_COMPATIBLE
	ambient_prd.dc = daysimNext(prd.dc);
	daysimSet(ambient_prd.dc, 0.0f);
#endif
#ifdef HIT_COUNT
	ambient_prd.hit_count = 0;
#endif
	const float tmin = ray_start(pos, AMBIENT_RAY_LENGTH);
	Ray ambient_ray = make_Ray(pos, dir, ambient_ray_type, -tmin, tmin);
	rtTrace(top_ambient, ambient_ray, ambient_prd);
#ifdef HIT_COUNT
	prd.hit_count += ambient_prd.hit_count;
#endif
	return ambient_prd.wsum > FTINY;
}
#endif /* AMBIENT_CELL */

RT_PROGRAM void any_hit_point_cloud_glass()
{
	float3 world_geometric_normal = normalize( rtTransformNormal( RT_OBJECT_TO_WORLD, geometric_normal ) );

	prd.backup.pos = ray.origin + t_hit * ray.direction;
	prd.backup.dir = faceforward(world_geometric_normal, -ray.direction, world_geometric_normal);
#ifdef AMBIENT_CELL
	prd.backup.cell = cell_hash(prd.backup.pos, prd.backup.dir);
#endif

	//TODO should probably use first intersection only and send transmitted ray
	rtIgnoreIntersection();
}

RT_PROGRAM void closest_hit_point_cloud()
{
	float3 world_geometric_normal = normalize( rtTransformNormal( RT_OBJECT_TO_WORLD, geometric_normal ) );

	prd.result.pos = ray.origin + t_hit * ray.direction;
	prd.result.dir = faceforward(world_geometric_normal, -ray.direction, world_geometric_normal);
#ifdef AMBIENT_CELL
	if (occupied(prd.result.pos, prd.result.dir, world_geometric_normal))
		prd.result = prd.backup;
	else
		prd.result.cell = cell_hash(prd.result.pos, prd.result.dir);
#endif
}

RT_PROGRAM void point_cloud_miss()
{
	prd.result = prd.backup;
}