/*
 * Proland: a procedural landscape rendering library.
 * Copyright (c) 2008-2011 INRIA
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */

/*
 * Proland is distributed under a dual-license scheme.
 * You can obtain a specific license from Inria: proland-licensing@inria.fr.
 */

/*
 * Authors: Eric Bruneton, Antoine Begault, Guillaume Piolat.
 */

/**
 * Precomputed Atmospheric Scattering
 * Copyright (c) 2008 INRIA
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 * 3. Neither the name of the copyright holders nor the names of its
 *    contributors may be used to endorse or promote products derived from
 *    this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
 * LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF
 * THE POSSIBILITY OF SUCH DAMAGE.
 */

/**
 * Author: Eric Bruneton
 */

#define OPTIMIZE
#define ATMO_FULL
#define HORIZON_HACK

#if !defined (M_PI)
#define M_PI 3.141592657
#endif

// ----------------------------------------------------------------------------
// PHYSICAL MODEL PARAMETERS
// ----------------------------------------------------------------------------

uniform float scale;
uniform float Rg;
uniform float Rt;
uniform float RL;

uniform float AVERAGE_GROUND_REFLECTANCE;

// Rayleigh
uniform float HR;
uniform float3 betaR;

// Mie
uniform float HM;
uniform float3 betaMSca;
uniform float3 betaMEx;
uniform float mieG;

// ----------------------------------------------------------------------------
// PARAMETERIZATION OPTIONS
// ----------------------------------------------------------------------------

uniform float TRANSMITTANCE_W;
uniform float TRANSMITTANCE_H;

uniform float SKY_W;
uniform float SKY_H;

uniform float RES_R;
uniform float RES_MU;
uniform float RES_MU_S;
uniform float RES_NU;

#define TRANSMITTANCE_NON_LINEAR
#define INSCATTER_NON_LINEAR

// ----------------------------------------------------------------------------
// PARAMETERIZATION FUNCTIONS
// ----------------------------------------------------------------------------

uniform float _Sun_Intensity;

uniform sampler2D _Sky_Transmittance;
uniform sampler2D _Sky_Irradiance;
uniform sampler3D _Sky_Inscatter;

float2 GetTransmittanceUV(float r, float mu) {
    float uR, uMu;
#ifdef TRANSMITTANCE_NON_LINEAR
    uR = sqrt((r - Rg) / (Rt - Rg));
    uMu = atan((mu + 0.15) / (1.0 + 0.15) * tan(1.5)) / 1.5;
#else
    uR = (r - Rg) / (Rt - Rg);
    uMu = (mu + 0.15) / (1.0 + 0.15);
#endif
    return float2(uMu, uR);
}

void GetTransmittanceRMu(float2 coord, out float r, out float muS) {
    r = coord.y / TRANSMITTANCE_H;
    muS = coord.x / TRANSMITTANCE_W;
#ifdef TRANSMITTANCE_NON_LINEAR
    r = Rg + (r * r) * (Rt - Rg);
    muS = -0.15 + tan(1.5 * muS) / tan(1.5) * (1.0 + 0.15);
#else
    r = Rg + r * (Rt - Rg);
    muS = -0.15 + muS * (1.0 + 0.15);
#endif
}

float2 GetIrradianceUV(float r, float muS) 
{
    float uR = (r - Rg) / (Rt - Rg);
    float uMuS = (muS + 0.2) / (1.0 + 0.2);
    return float2(uMuS, uR);
}

void GetIrradianceRMuS(float2 coord, out float r, out float muS) 
{
    r = Rg + (coord.y - 0.5) / (SKY_H - 1.0) * (Rt - Rg);
    muS = -0.2 + (coord.x - 0.5) / (SKY_W - 1.0) * (1.0 + 0.2);
}

float4 Texture4D(sampler3D table, float r, float mu, float muS, float nu)
{

    float H = sqrt(Rt * Rt - Rg * Rg);
    float rho = sqrt(r * r - Rg * Rg);
#ifdef INSCATTER_NON_LINEAR
    float rmu = r * mu;
    float delta = rmu * rmu - r * r + Rg * Rg;
    float4 cst = rmu < 0.0 && delta > 0.0 ? float4(1.0, 0.0, 0.0, 0.5 - 0.5 / RES_MU) : float4(-1.0, H * H, H, 0.5 + 0.5 / RES_MU);
    float uR = 0.5 / RES_R + rho / H * (1.0 - 1.0 / float(RES_R));
    float uMu = cst.w + (rmu * cst.x + sqrt(delta + cst.y)) / (rho + cst.z) * (0.5 - 1.0 / RES_MU);
    // paper formula
    //float uMuS = 0.5 / float(RES_MU_S) + max((1.0 - exp(-3.0 * muS - 0.6)) / (1.0 - exp(-3.6)), 0.0) * (1.0 - 1.0 / float(RES_MU_S));
    // better formula
    float uMuS = 0.5 / RES_MU_S + (atan(max(muS, -0.1975) * tan(1.26 * 1.1)) / 1.1 + (1.0 - 0.26)) * 0.5 * (1.0 - 1.0 / RES_MU_S);
#else
    float uR = 0.5 / RES_R + rho / H * (1.0 - 1.0 / RES_R);
    float uMu = 0.5 / RES_MU + (mu + 1.0) / 2.0 * (1.0 - 1.0 / RES_MU);
    float uMuS = 0.5 / RES_MU_S + max(muS + 0.2, 0.0) / 1.2 * (1.0 - 1.0 / RES_MU_S);
#endif
    float _lerp = (nu + 1.0) / 2.0 * (RES_NU - 1.0);
    float uNu = floor(_lerp);
    _lerp = _lerp - uNu;
    return tex3Dlod(table, float4((uNu + uMuS) / RES_NU, uMu, uR, 0)) * (1.0 - _lerp) +
           tex3Dlod(table, float4((uNu + uMuS + 1.0) / RES_NU, uMu, uR, 0)) * _lerp;
}

// ----------------------------------------------------------------------------
// UTILITY FUNCTIONS
// ----------------------------------------------------------------------------

// nearest intersection of ray r,mu with ground or top atmosphere boundary
// mu=cos(ray zenith angle at ray origin)
float Limit(float r, float mu) 
{
    float dout = -r * mu + sqrt(r * r * (mu * mu - 1.0) + RL * RL);
    float delta2 = r * r * (mu * mu - 1.0) + Rg * Rg;
    if (delta2 >= 0.0) {
        float din = -r * mu - sqrt(delta2);
        if (din >= 0.0) {
            dout = min(dout, din);
        }
    }
    return dout;
}

// optical depth for ray (r,mu) of length d, using analytic formula
// (mu=cos(view zenith angle)), intersections with ground ignored
// H=height scale of exponential density function
float OpticalDepth(float H, float r, float mu, float d) 
{
    float a = sqrt((0.5/H)*r);
    float2 a01 = a*float2(mu, mu + d / r);
    float2 a01s = sign(a01);
    float2 a01sq = a01*a01;
    float x = a01s.y > a01s.x ? exp(a01sq.x) : 0.0;
    float2 y = a01s / (2.3193*abs(a01) + sqrt(1.52*a01sq + 4.0)) * float2(1.0, exp(-d/H*(d/(2.0*r)+mu)));
    return sqrt((6.2831*H)*r) * exp((Rg-r)/H) * (x + dot(y, float2(1.0, -1.0)));
}

// transmittance(=transparency) of atmosphere for infinite ray (r,mu)
// (mu=cos(view zenith angle)), intersections with ground ignored
float3 Transmittance(float r, float mu) 
{
    float2 uv = GetTransmittanceUV(r, mu);
    return tex2Dlod(_Sky_Transmittance, float4(uv,0,0)).rgb;
}

// transmittance(=transparency) of atmosphere for ray (r,mu) of length d
// (mu=cos(view zenith angle)), intersections with ground ignored
// uses analytic formula instead of transmittance texture
float3 AnalyticTransmittance(float r, float mu, float d) 
{
    return exp(- betaR * OpticalDepth(HR, r, mu, d) - betaMEx * OpticalDepth(HM, r, mu, d));
}

// transmittance(=transparency) of atmosphere for infinite ray (r,mu)
// (mu=cos(view zenith angle)), or zero if ray intersects ground
float3 TransmittanceWithShadow(float r, float mu) 
{
    return mu < -sqrt(1.0 - (Rg / r) * (Rg / r)) ? float3(0,0,0) : Transmittance(r, mu);
}

// transmittance(=transparency) of atmosphere between x and x0
// assume segment x,x0 not intersecting ground
// r=||x||, mu=cos(zenith angle of [x,x0) ray at x), v=unit direction vector of [x,x0) ray
float3 Transmittance(float r, float mu, float3 v, float3 x0) {
    float3 result;
    float r1 = length(x0);
    float mu1 = dot(x0, v) / r;
    if (mu > 0.0) {
        result = min(Transmittance(r, mu) / Transmittance(r1, mu1), 1.0);
    } else {
        result = min(Transmittance(r1, -mu1) / Transmittance(r, -mu), 1.0);
    }
    return result;
}

// transmittance(=transparency) of atmosphere between x and x0
// assume segment x,x0 not intersecting ground
// d = distance between x and x0, mu=cos(zenith angle of [x,x0) ray at x)
float3 Transmittance(float r, float mu, float d) 
{
    float3 result;
    float r1 = sqrt(r * r + d * d + 2.0 * r * mu * d);
    float mu1 = (r * mu + d) / r1;
    if (mu > 0.0) {
        result = min(Transmittance(r, mu) / Transmittance(r1, mu1), 1.0);
    } else {
        result = min(Transmittance(r1, -mu1) / Transmittance(r, -mu), 1.0);
    }
    return result;
}

float3 Irradiance(sampler2D samp, float r, float muS) 
{
    float2 uv = GetIrradianceUV(r, muS);
    return tex2Dlod(samp, float4(uv,0,0)).rgb;
}

// Rayleigh phase function
float PhaseFunctionR(float mu) 
{
    return (3.0 / (16.0 * M_PI)) * (1.0 + mu * mu);
}

// Mie phase function
float PhaseFunctionM(float mu) 
{
    return 1.5 * 1.0 / (4.0 * M_PI) * (1.0 - mieG*mieG) * pow(1.0 + (mieG*mieG) - 2.0*mieG*mu, -3.0/2.0) * (1.0 + mu * mu) / (2.0 + mieG*mieG);
}

// approximated single Mie scattering (cf. approximate Cm in paragraph "Angular precision")
float3 GetMie(float4 rayMie) 
{ 	// rayMie.rgb=C*, rayMie.w=Cm,r
    return rayMie.rgb * rayMie.w / max(rayMie.r, 1e-4) * (betaR.r / betaR);
}

float SQRT(float f, float err) {
#ifdef OPTIMIZE
    return sqrt(f);
#else
    return f >= 0.0 ? sqrt(f) : err;
#endif
}

// ----------------------------------------------------------------------------
// PUBLIC FUNCTIONS
// ----------------------------------------------------------------------------

// incident sun light at given position (radiance)
// r=length(x)
// muS=dot(x,s) / r
float3 SunRadiance(float r, float muS) {
#if defined(ATMO_SUN_ONLY) || defined(ATMO_FULL)
    return TransmittanceWithShadow(r, muS) * _Sun_Intensity;
#elif defined(ATMO_NONE)
    return _Sun_Intensity.xxx;
#else
    return float3(0,0,0);
#endif
}

// incident sky light at given position, integrated over the hemisphere (irradiance)
// r=length(x)
// muS=dot(x,s) / r
float3 SkyIrradiance(float r, float muS) {
#if defined(ATMO_SKY_ONLY) || defined(ATMO_FULL)
    return Irradiance(_Sky_Irradiance, r, muS) * _Sun_Intensity;
#else
    return float3(0,0,0);
#endif
}

// single scattered sunlight between two points
// camera=observer
// viewdir=unit vector towards observed point
// sundir=unit vector towards the sun
// return scattered light and extinction coefficient
float3 SkyRadiance(float3 camera, float3 viewdir, float3 sundir, out float3 extinction, float shaftWidth)
{
#if defined(ATMO_INSCATTER_ONLY) || defined(ATMO_FULL)
	float3 result = float3(0,0,0);
	extinction = float3(1,1,1);
	
	camera *= scale;
	camera += viewdir * max(shaftWidth, 0.0);
	float r = length(camera);
	float rMu = dot(camera, viewdir);
	float mu = rMu / r;
	float r0 = r;
	float mu0 = mu;

    float deltaSq = SQRT(rMu * rMu - r * r + Rt*Rt, 1e30);
    float din = max(-rMu - deltaSq, 0.0);
    if (din > 0.0) {
        camera += din * viewdir;
        rMu += din;
        mu = rMu / Rt;
        r = Rt;
    }

    if (r <= Rt) 
    {
        float nu = dot(viewdir, sundir);
        float muS = dot(camera, sundir) / r;

        float4 inScatter = Texture4D(_Sky_Inscatter, r, rMu / r, muS, nu);
        if (shaftWidth > 0.0) 
        {
            if (mu > 0.0) {
                inScatter *= min(Transmittance(r0, mu0) / Transmittance(r, mu), 1.0).rgbr;
            } else {
                inScatter *= min(Transmittance(r, -mu) / Transmittance(r0, -mu0), 1.0).rgbr;
            }
        }
        extinction = Transmittance(r, mu);

        float3 inScatterM = GetMie(inScatter);
        float phase = PhaseFunctionR(nu);
        float phaseM = PhaseFunctionM(nu);
        result = inScatter.rgb * phase + inScatterM * phaseM;
    } 

    return result * _Sun_Intensity;
#else
    extinction = float3(1,1,1);
    return float3(0,0,0);
#endif
}

void SunRadianceAndSkyIrradiance(float3 worldP, float3 worldN, float3 worldS, out float3 sunL, out float3 skyE)
{
	worldP *= scale;
    float r = length(worldP);
    if (r < 0.9 * Rg) {
        worldP.z += Rg;
        r = length(worldP);
    }
    float3 worldV = worldP / r; // vertical vector
    float muS = dot(worldV, worldS);

    float sunOcclusion = 1.0;// - sunShadow;
    sunL = SunRadiance(r, muS) * sunOcclusion;

    // ambient occlusion due only to slope, does not take self shadowing into account
    float skyOcclusion = (1.0 + dot(worldV, worldN)) * 0.5;
    // factor 2.0 : hack to increase sky contribution (numerical simulation of
    // "precompued atmospheric scattering" gives less luminance than in reality)
    skyE = 2.0 * SkyIrradiance(r, muS) * skyOcclusion;
}

// single scattered sunlight between two points
// camera=observer
// point=point on the ground
// sundir=unit vector towards the sun
// return scattered light and extinction coefficient
float3 InScattering(float3 camera, float3 _point, float3 sundir, out float3 extinction, float shaftWidth) 
{
#if defined(ATMO_INSCATTER_ONLY) || defined(ATMO_FULL)

	camera *= scale;
	_point *= scale;

    float3 result;
    float3 viewdir = _point - camera;
    float d = length(viewdir);
    viewdir = viewdir / d;
    
    float r = length(camera);
    if (r < 0.9 * Rg) {
        camera.z += Rg;
        _point.z += Rg;
        r = length(camera);
    }
    
    float rMu = dot(camera, viewdir);
    float mu = rMu / r;
    float r0 = r;
    float mu0 = mu;
    _point -= viewdir * clamp(shaftWidth, 0.0, d);

    float deltaSq = SQRT(rMu * rMu - r * r + Rt*Rt, 1e30);
    float din = max(-rMu - deltaSq, 0.0);
    if (din > 0.0 && din < d) {
        camera += din * viewdir;
        rMu += din;
        mu = rMu / Rt;
        r = Rt;
        d -= din;
    }

    if (r <= Rt) {
        float nu = dot(viewdir, sundir);
        float muS = dot(camera, sundir) / r;

        float4 inScatter;

        if (r < Rg + 2000.0) {
            // avoids imprecision problems in aerial perspective near ground
            float f = (Rg + 2000.0) / r;
            r = r * f;
            rMu = rMu * f;
            _point = _point * f;
        }

        float r1 = length(_point);
        float rMu1 = dot(_point, viewdir);
        float mu1 = rMu1 / r1;
        float muS1 = dot(_point, sundir) / r1;

#ifdef ANALYTIC_TRANSMITTANCE
        extinction = min(AnalyticTransmittance(r, mu, d), 1.0);
#else
        if (mu > 0.0) {
            extinction = min(Transmittance(r, mu) / Transmittance(r1, mu1), 1.0);
        } else {
            extinction = min(Transmittance(r1, -mu1) / Transmittance(r, -mu), 1.0);
        }
#endif

#ifdef HORIZON_HACK
        const float EPS = 0.004;
        float lim = -sqrt(1.0 - (Rg / r) * (Rg / r));
        if (abs(mu - lim) < EPS) {
            float a = ((mu - lim) + EPS) / (2.0 * EPS);

            mu = lim - EPS;
            r1 = sqrt(r * r + d * d + 2.0 * r * d * mu);
            mu1 = (r * mu + d) / r1;
            float4 inScatter0 = Texture4D(_Sky_Inscatter, r, mu, muS, nu);
            float4 inScatter1 = Texture4D(_Sky_Inscatter, r1, mu1, muS1, nu);
            float4 inScatterA = max(inScatter0 - inScatter1 * extinction.rgbr, 0.0);

            mu = lim + EPS;
            r1 = sqrt(r * r + d * d + 2.0 * r * d * mu);
            mu1 = (r * mu + d) / r1;
            inScatter0 = Texture4D(_Sky_Inscatter, r, mu, muS, nu);
            inScatter1 = Texture4D(_Sky_Inscatter, r1, mu1, muS1, nu);
            float4 inScatterB = max(inScatter0 - inScatter1 * extinction.rgbr, 0.0);

            inScatter = lerp(inScatterA, inScatterB, a);
        } 
        else {
            float4 inScatter0 = Texture4D(_Sky_Inscatter, r, mu, muS, nu);
            float4 inScatter1 = Texture4D(_Sky_Inscatter, r1, mu1, muS1, nu);
            inScatter = max(inScatter0 - inScatter1 * extinction.rgbr, 0.0);
        }
#else
        float4 inScatter0 = Texture4D(_Sky_Inscatter, r, mu, muS, nu);
        float4 inScatter1 = Texture4D(_Sky_Inscatter, r1, mu1, muS1, nu);
        inScatter = max(inScatter0 - inScatter1 * extinction.rgbr, 0.0);
#endif

        //cancels inscatter when sun hidden by mountains
        //TODO smoothstep values depend on horizon angle in sun direction
        //inScatter.w *= smoothstep(0.035, 0.07, muS);

        // avoids imprecision problems in Mie scattering when sun is below horizon
        inScatter.w *= smoothstep(0.00, 0.02, muS);

        float3 inScatterM = GetMie(inScatter);
        float phase = PhaseFunctionR(nu);
        float phaseM = PhaseFunctionM(nu);
        result = inScatter.rgb * phase + inScatterM * phaseM;
    } 
    else {
        result = float3(0,0,0);
        extinction = float3(1,1,1);
    }

    return result * _Sun_Intensity;
#else
    extinction = float3(1,1,1);
    return float3(0,0,0);
#endif
}

















