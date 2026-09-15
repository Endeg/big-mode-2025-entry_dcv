@echo off
glslc -fshader-stage=vert src\simple.vert.glsl -o src\simple.vert.spv
glslc -fshader-stage=frag src\simple.frag.glsl -o src\simple.frag.spv
