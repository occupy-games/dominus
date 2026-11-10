# Terrain references reviewed

## layered-map

Reviewed `MapGeneratorSync`, `GridCell`, `EdgeVertices`, configuration and the
generation entry point in [wh1te-tiger/layered-map](https://github.com/wh1te-tiger/layered-map/tree/main/Assets/Scripts/WorldGeneration).
It builds separate meshes at height thresholds using marching squares and
interpolated edge crossings. This agrees with Dominus's current contour model.
Useful follow-ups are per-layer/chunk caches, shared edge samples and explicit
checks for all 16 cell configurations. Vertex sharing must respect the sharp
normal break between caps and walls. The inspected entry point generates on
startup; it does not establish interactive drag semantics.

## stepped-landscape

Reviewed `MapGenerator` and [GeometryGenerator](https://github.com/Liagson/stepped-landscape/blob/main/Assets/Src/GeometryGenerator.cs).
It uses relaxed Voronoi cells, quantized noise heights and triangulated cell
caps with downward walls. Irregular cells reduce the appearance of a square
grid. Adopting that topology would also require new adjacency, picking and edit
rules. It is a generation reference rather than a layer-drag implementation.

## Application to Dominus

Keep authoritative terrain and drag transactions in simulation. Derive caps
and walls in presentation. Preserve continuous edge interpolation and test
diagonal connectivity, closed walls, flat denominators and protected plots.
Investigate dirty-region rebuilding before increasing terrain resolution.
Do not introduce visual warping that disagrees with picking or navigation.
No source code from these repositories has been copied into the game.
