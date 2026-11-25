#version 440
// R658 composite, derived from edgefade.frag (Meridiana abde90d8, R624/R633).
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 area;
    float radius;
    vec4 fadeRect;
    float topBand;
    float bottomBand;
    float topInset;
    float bottomInset;
    float room;
};
layout(binding = 1) uniform sampler2D source;
void main() {
    vec2 p = qt_TexCoord0 * area;
    vec2 q = abs(p - area * .5) - area * .5 + radius;
    float dist = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
    float k = 1.0 - smoothstep(-fwidth(dist)*.5, fwidth(dist)*.5, dist);
    vec2 f = p - fadeRect.xy;
    if (f.x >= 0.0 && f.x < fadeRect.z-room && f.y >= 0.0 && f.y < fadeRect.w) {
        float top = f.y-topInset, bottom = fadeRect.w-bottomInset-f.y;
        // Held head pixels are already composited above the viewport here.
        if (top >= 0.0 && bottom >= 0.0) {
            if (topBand > 0.0) k *= smoothstep(0.0, topBand, top);
            if (bottomBand > 0.0) k *= smoothstep(0.0, bottomBand, bottom);
        }
    }
    fragColor = texture(source, qt_TexCoord0) * (k * qt_Opacity);
}
