#include <metal_stdlib>
using namespace metal;

struct HouseVertexIn {
    float4 position;
    float2 uv;
    float4 tint;
    float emissive;
    float depthKey;
};

struct HouseVertexOut {
    float4 position [[position]];
    float2 uv;
    float4 tint;
    float emissive;
    float depthKey;
};

struct HouseUniforms {
    float4x4 viewProj;
    float3 ambientColor;
    float ambientStrength;
    float3 pointLightPos;
    float3 pointLightColor;
    float pointLightStrength;
    float2 viewportSize;
    float time;
    float tvOn;
    float lampOn;
};

vertex HouseVertexOut house_vertex(uint vid [[vertex_id]],
                                   constant HouseVertexIn *verts [[buffer(0)]],
                                   constant HouseUniforms &u [[buffer(1)]]) {
    HouseVertexIn v = verts[vid];
    HouseVertexOut o;
    o.position = u.viewProj * v.position;
    o.uv = v.uv;
    o.tint = v.tint;
    o.emissive = v.emissive;
    o.depthKey = v.depthKey;
    return o;
}

fragment float4 house_fragment(HouseVertexOut in [[stage_in]],
                               texture2d<float> tex [[texture(0)]],
                               sampler samp [[sampler(0)]],
                               constant HouseUniforms &u [[buffer(1)]]) {
    float4 albedo = tex.sample(samp, in.uv) * in.tint;
    if (albedo.a < 0.05) { discard_fragment(); }

    float3 n = normalize(float3(0.0, 0.0, 1.0));
    float3 l = normalize(u.pointLightPos - float3(0.0));
    float diff = max(dot(n, l), 0.0) * u.pointLightStrength * u.lampOn;
    float3 toLight = u.pointLightPos - float3(in.position.xy, 0.0);
    float dist = length(toLight);
    float atten = 1.0 / (1.0 + dist * dist * 0.0008);
    float3 point = u.pointLightColor * diff * atten * u.lampOn;

    float3 lit = albedo.rgb * (u.ambientColor * u.ambientStrength + point);
    lit += albedo.rgb * in.emissive;
    if (u.tvOn > 0.5 && in.emissive > 0.5) {
        float flick = 0.85 + 0.15 * sin(u.time * 8.0 + in.uv.x * 20.0);
        lit += float3(0.35, 0.55, 0.95) * flick * 0.6;
    }
    return float4(lit, albedo.a);
}

struct FullscreenOut {
    float4 position [[position]];
    float2 uv;
};

vertex FullscreenOut fullscreen_vertex(uint vid [[vertex_id]]) {
    float2 pos[4] = { float2(-1, -1), float2(1, -1), float2(-1, 1), float2(1, 1) };
    float2 uv[4] = { float2(0, 1), float2(1, 1), float2(0, 0), float2(1, 0) };
    FullscreenOut o;
    o.position = float4(pos[vid], 0, 1);
    o.uv = uv[vid];
    return o;
}

fragment float4 bokeh_background(FullscreenOut in [[stage_in]],
                                 constant float &time [[buffer(0)]]) {
    float2 uv = in.uv;
    float3 base = float3(0.04, 0.05, 0.09);
    float vignette = smoothstep(1.2, 0.2, length(uv - 0.5) * 1.4);
    float3 col = base * (0.6 + 0.4 * vignette);
    for (int i = 0; i < 18; i++) {
        float fi = float(i);
        float2 p = float2(fract(sin(fi * 12.9898) * 43758.5453), fract(cos(fi * 78.233) * 12345.67));
        p = p * 0.9 + 0.05;
        float r = 0.02 + fract(fi * 0.17) * 0.04;
        float d = length(uv - p);
        float glow = exp(-d * d / (r * r)) * (0.08 + 0.06 * sin(time + fi));
        float3 c = (i % 3 == 0) ? float3(1.0, 0.7, 0.35) : ((i % 3 == 1) ? float3(0.45, 0.6, 1.0) : float3(0.9, 0.5, 0.75));
        col += c * glow;
    }
    return float4(col, 1.0);
}

fragment float4 composite_tiltshift(FullscreenOut in [[stage_in]],
                                    texture2d<float> scene [[texture(0)]],
                                    texture2d<float> bloom [[texture(1)]],
                                    sampler samp [[sampler(0)]],
                                    constant float2 &viewport [[buffer(0)]]) {
    float2 uv = in.uv;
    float blurAmt = smoothstep(0.0, 0.35, abs(uv.y - 0.5)) * 2.5;
    float2 px = float2(1.0 / viewport.x, 1.0 / viewport.y) * blurAmt;
    float3 c = float3(0);
    c += scene.sample(samp, uv + px * float2(1, 0)).rgb * 0.2;
    c += scene.sample(samp, uv - px * float2(1, 0)).rgb * 0.2;
    c += scene.sample(samp, uv + px * float2(0, 1)).rgb * 0.2;
    c += scene.sample(samp, uv - px * float2(0, 1)).rgb * 0.2;
    c += scene.sample(samp, uv).rgb * 0.2;
    float3 b = bloom.sample(samp, uv).rgb;
    c += b * 1.2;
    float vig = smoothstep(1.1, 0.35, length(uv - 0.5) * 1.5);
    c *= 0.75 + 0.25 * vig;
    return float4(c, 1.0);
}

fragment float4 bloom_threshold(FullscreenOut in [[stage_in]],
                                texture2d<float> scene [[texture(0)]],
                                sampler samp [[sampler(0)]]) {
    float3 c = scene.sample(samp, in.uv).rgb;
    float br = max(max(c.r, c.g), c.b);
    float t = smoothstep(0.55, 0.95, br);
    return float4(c * t, 1.0);
}

fragment float4 blur_pass(FullscreenOut in [[stage_in]],
                          texture2d<float> src [[texture(0)]],
                          sampler samp [[sampler(0)]],
                          constant float2 &dir [[buffer(0)]]) {
    float2 px = dir / float2(1200, 800);
    float3 c = float3(0);
    c += src.sample(samp, in.uv + px * -2.0).rgb * 0.05;
    c += src.sample(samp, in.uv + px * -1.0).rgb * 0.15;
    c += src.sample(samp, in.uv).rgb * 0.6;
    c += src.sample(samp, in.uv + px * 1.0).rgb * 0.15;
    c += src.sample(samp, in.uv + px * 2.0).rgb * 0.05;
    return float4(c, 1.0);
}
