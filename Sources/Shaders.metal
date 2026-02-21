#include <metal_stdlib>
using namespace metal;

// Per-vertex data (unit cube template)
struct VertexIn {
    float2 basePos;       // x, y_base relative to cube center
    float heightFactor;   // 0 = ground level, 1 = top level (offset by cubeHeight)
    uint faceIndex;       // 0=top, 1=left, 2=right
};

// Per-instance data (one per visible cube)
struct InstanceIn {
    float4 posHeightScale;  // xy=screenPos, z=cubeHeight, w=scale
    float4 topColor;        // rgb, a=alpha for whole cube
    float4 leftColor;       // rgb
    float4 rightColor;      // rgb
};

struct VertexOut {
    float4 position [[position]];
    float4 color;
};

vertex VertexOut vertex_main(uint vertexId [[vertex_id]],
                             uint instanceId [[instance_id]],
                             constant VertexIn *vertices [[buffer(0)]],
                             constant InstanceIn *instances [[buffer(1)]],
                             constant float2 &viewportSize [[buffer(2)]]) {
    VertexIn v = vertices[vertexId];
    InstanceIn inst = instances[instanceId];

    float2 screenPos = inst.posHeightScale.xy;
    float cubeHeight = inst.posHeightScale.z;
    float scale = inst.posHeightScale.w;
    float alpha = inst.topColor.a;

    // Compute vertex position: base + height offset
    float2 pos = v.basePos;
    pos.y += v.heightFactor * cubeHeight;

    // Apply scale (expand from center)
    pos *= scale;

    // Translate to screen position
    pos += screenPos;

    // Convert pixel coords to NDC (-1..1)
    float2 ndc;
    ndc.x = (pos.x / viewportSize.x) * 2.0 - 1.0;
    ndc.y = (pos.y / viewportSize.y) * 2.0 - 1.0;

    // Select face color
    float3 c;
    if (v.faceIndex == 0) c = inst.topColor.rgb;
    else if (v.faceIndex == 1) c = inst.leftColor.rgb;
    else c = inst.rightColor.rgb;

    VertexOut out;
    out.position = float4(ndc, 0.0, 1.0);
    out.color = float4(c, alpha);
    return out;
}

fragment float4 fragment_main(VertexOut in [[stage_in]]) {
    return in.color;
}
