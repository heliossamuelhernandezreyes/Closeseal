shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back;
uniform vec4 paint_color : source_color = vec4(0.55,0.39,0.16,1.0);
uniform float stripes = 0.0;
uniform float wear = 0.22;
varying vec3 world_position;
void vertex(){world_position=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
float hash(vec3 p){return fract(sin(dot(p,vec3(17.71,91.37,43.51)))*43758.5453);}
void fragment(){
    float grain=hash(floor(world_position*75.0));
    float abrasion=smoothstep(0.70,0.97,hash(floor(world_position*8.0)))*wear;
    float stripe=step(0.5,fract((UV.x+UV.y*0.14)*10.0));
    vec3 base=mix(paint_color.rgb,vec3(0.028,0.032,0.033),stripe*stripes);
    ALBEDO=mix(base,vec3(0.16,0.14,0.11),abrasion)*(0.92+grain*0.08);
    ROUGHNESS=0.89;METALLIC=0.02;
}
