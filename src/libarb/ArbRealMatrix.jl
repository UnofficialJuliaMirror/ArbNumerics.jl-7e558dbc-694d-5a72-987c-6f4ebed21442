# heavily influenced by and mostly of the Arb C interface used in Nemo.jl
        
#=
typedef struct
{
    arb_ptr entries;
    slong r;
    slong c;
    arb_ptr * rows;
}
arb_mat_struct;
=#

abstract type AbstractArbMatrix{T} <: AbstractMatrix{T} end
abstract type AnyArbMatrix{P, T} <: AbstractArbMatrix{T} end
            
mutable struct ArbRealMatrix{P} <: AnyArbMatrix{P, ArbReal}
    entries::Ptr{ArbReal{P}}
    nrows::Int
    ncols::Int
    rows::Ptr{Ptr{ArbReal{P}}}

   function ArbRealMatrix{P}(nrows::Int, ncols::Int) where {P}
       nrows, ncols = ncols, nrows
       z = new{P}() # z = new{P}(Ptr{ArbReal{P}}(0), 0, 0, Ptr{Ptr{ArbReal{P}}}(0))
       arb_mat_init(z, nrows, ncols)
       finalizer(arb_mat_clear, z)
       return z
   end

   function ArbRealMatrix(nrows::Int, ncols::Int)
        P = workingprecision(ArbReal)
        return ArbRealMatrix{P}(nrows, ncols)
   end
end

function arb_mat_clear(x::ArbRealMatrix) where {P}
    ccall(@libarb(arb_mat_clear), Cvoid, (Ref{ArbRealMatrix}, ), x)
    return nothing
end

function arb_mat_init(x::ArbRealMatrix{P}, nrows::Int, ncols::Int) where {P}
    ccall(@libarb(arb_mat_init), Cvoid, (Ref{ArbRealMatrix}, Cint, Cint), x, nrows, ncols)
    return nothing
end

Base.size(x::ArbRealMatrix{P}) where {P} = (x.ncols, x.rows)

@inline function checkbounds(x::ArbRealMatrix{P}, r::Int, c::Int) where {P}
    ok = 0 < r <= x.nrows && 0 < c <= x.ncols
    if !ok
        throw(BoundsError("($r, $c) not in 1:$(x.nrows), 1:$(x.ncols)"))
    end
    return nothing
end

@inline function checkbounds(x::ArbRealMatrix{P}, rc::Int) where {P}
    ok = 0 < rc <= x.nrows * x.ncols
    if !ok
        throw(BoundsError("($rc) not in 1:$(x.nrows * x.ncols)"))
    end
    return nothing
end

@inline function Base.getindex(x::ArbRealMatrix{P}, rowidx::Int, colidx::Int) where {P}
    rowidx, colidx = colidx, rowidx
    checkbounds(x, rowidx, colidx)

   z = ArbReal{P}()
   GC.@preserve x begin
       v = ccall(@libarb(arb_mat_entry_ptr), Ptr{ArbReal},
                 (Ref{ArbRealMatrix}, Int, Int), x, rowidx - 1, colidx - 1)
       ccall(@libarb(arb_set), Cvoid, (Ref{ArbReal}, Ptr{ArbReal}), z, v)
   end
   return z
end

@inline function Base.getindex(x::ArbRealMatrix{P}, linearidx::Int) where {P}
    rowidx, colidx = linear_to_cartesian(x.nrows, linearidx)
    return getindex(x, rowidx, colidx)
end

function Base.getindex(x::ArbRealMatrix{P}, linearidxs::Array{Int,1}) where {P}
    nrows = x.nrows
    values = Vector{ArbReal{P}}(undef, length(linearidxs))
    valueidx = 1
    for idx in linearidx
        rowidx, colidx = linear_to_cartesian(nrows, idx)
        values[valueidx] = getindex(x, rowidx, colidx)
        valueidx += 1
    end
    return values
end


function Base.setindex!(x::ArbRealMatrix{P}, z::ArbReal{P}, linearidx::Int) where {P}
    rowidx, colidx = linear_to_cartesian(x.nrows, linearidx)
    rowidx, colidx = colidx, rowidx
    checkbounds(x, rowidx, colidx)
   
    GC.@preserve x begin
        ptr = ccall(@libarb(arb_mat_entry_ptr), Ptr{ArbReal}, (Ref{ArbRealMatrix}, Cint, Cint), x, rowidx-1, colidx-1)
        ccall(@libarb(arb_set), Cvoid, (Ptr{ArbReal}, Ref{ArbReal}), ptr, z)
        end
    return z
end

function Base.setindex!(x::ArbRealMatrix{P}, z::ArbReal{P}, rowidx::Int, colidx::Int) where {P}
    rowidx, colidx = colidx, rowidx
    checkbounds(x, rowidx, colidx)
    
    GC.@preserve x begin
        ptr = ccall(@libarb(arb_mat_entry_ptr), Ptr{ArbReal}, (Ref{ArbRealMatrix}, Cint, Cint), x, rowidx-1, colidx-1)
        ccall(@libarb(arb_set), Cvoid, (Ptr{ArbReal}, Ref{ArbReal}), ptr, z)
        end
    return z
end

function Base.setindex!(x::ArbRealMatrix{P}, z::Array{ArbReal{P},1}, linearidx::Array{Int,1}) where {P}
    for (az, alinearidx) in (z, linearidx)
        setindex!(x, ax, alinearidx)
    end
    return x
end

# constructors

function ArbRealMatrix{P}(x::M) where {P, T<:AbstractFloat, M<:AbstractMatrix{T}}
   nrows, ncols = size(x)
   arm = ArbRealMatrix{P}(nrows, ncols)
   for row in 1:nrows
       for col in 1:ncols
           afloat = x[row,col]
           arm[row,col]  = ArbReal{P}(afloat)
       end
    end
    return arm
end

function Matrix{T}(x::A) where {P, T<:AbstractFloat, A<:ArbRealMatrix{P}}
   nrows, ncols = x.ncols, x.nrows
   fpm = reshape(zeros(nrows*ncols), (nrows, ncols))
   for row in 1:nrows
       for col in 1:ncols
           aarb = x[row,col]
           fpm[row,col]  = T(aarb)
       end
    end
    return fpm
end


function ArbRealMatrix{P}(x::M) where {P, T<:Integer, M<:AbstractMatrix{T}}
   nrows, ncols = size(x)
   arm = ArbRealMatrix{P}(nrows, ncols)
   for row in 1:nrows
       for col in 1:ncols
           anint = x[row,col]
           arm[row,col]  = ArbReal{P}(anint)
       end
    end
    return arm
end

function Matrix{T}(x::A) where {P, T<:Integer, A<:ArbRealMatrix{P}}
   nrows, ncols = x.ncols, x.nrows
   intm = reshape(zeros(nrows*ncols), (nrows, ncols))
   for row in 1:nrows
       for col in 1:ncols
           aarb = x[row,col]
           intm[row,col]  = T(aarb)
       end
    end
    return intm
end


# void arb_mat_mul(arb_mat_t res, const arb_mat_t mat1, const arb_mat_t mat2, slong prec)
function Base.:(*)(x::ArbRealMatrix{P}, y::ArbRealMatrix{P}) where {P}
    if x.ncols !== y.nrows
        throw(ErrorException("Dimension Mismatach: x($(x.nrows), $(x.ncols)) y($(y.nrows), $(y.ncols))"))
    end
    z = ArbRealMatrix{P}(x.nrows, y.ncols)
    ccall(@libarb(arb_mat_mul), Cvoid, (Ref{ArbRealMatrix}, Ref{ArbRealMatrix}, Ref{ArbRealMatrix}, Cint), z, x, y, P)
    return z
end

    
function Base.show(io::IO, ::MIME"text/plain", a::ArbRealMatrix{P}) where {P}
    c = a.nrows
    r = a.ncols
    println(io, string(r,"x",c," Array{ArbReal{",P,"},2}"))
    for i = 1:r
        for j = 1:c
           print(io, a[i, j])
           if j != c
               print(io, " ")
           end
        end
        if i != r
           println(io, "")
        end
    end
end