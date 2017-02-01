#version 110

uniform sampler2DRect color;
uniform sampler2DRect depth;

void main()
{
    //Multiply color by texture
    gl_FragData[0] = texture2DRect(color, gl_TexCoord[0].xy);
    
    // Linearize Depth
    vec4 depth = texture2DRect(depth, gl_TexCoord[0].xy);
    
    // Assume the clipping planes are correct?
    float f = 1000.0;
    float n = 0.1;
    float z = (2.0 * n) / (f + n - depth.r * (f - n));

    gl_FragData[1] = vec4(depth);
}
