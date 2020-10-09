struct DESPOT{S,A,O}
    scenarios::Vector{Vector{Pair{Int,S}}}
    children::Vector{Vector{Int}} # to children *ba nodes*
    parent_b::Vector{Int} # maps to parent *belief node*
    parent::Vector{Int} # maps to the parent *ba node*
    Delta::Vector{Int}
    mu::Vector{Float64} # needed for ba_mu, excess_uncertainty
    l::Vector{Float64} # needed to select action, excess_uncertainty
    U::Vector{Float64} # needed for blocking
    l_0::Vector{Float64} # needed for find_blocker, backup of l and mu
    obs::Vector{O}

    ba_children::Vector{Vector{Int}}
    ba_l::Vector{Float64} # needed for next_best
    ba_mu::Vector{Float64} # needed for next_best
    ba_U::Vector{Float64}
    ba_rho::Vector{Float64} # needed for backup
    ba_Rsum::Vector{Float64} # needed for backup
    ba_action::Vector{A}

    _discount::Float64 # for inferring L in visualization
end

function DESPOT(p::PL_DESPOTPlanner, b_0)
    S = statetype(p.pomdp)
    A = actiontype(p.pomdp)
    O = obstype(p.pomdp)
    root_scenarios = [i=>rand(p.rng, b_0) for i in 1:p.sol.K]

    scenario_belief = ScenarioBelief(root_scenarios, p.rs, 0, b_0)
    L_0, U_0 = bounds(p.bounds, p.pomdp, scenario_belief)

    if p.sol.bounds_warnings
        bounds_sanity_check(p.pomdp, scenario_belief, L_0, U_0)
    end

    return DESPOT{S,A,O}([root_scenarios],
                         [Int[]],
                         [0],
                         [0],
                         [0],
                         [max(L_0, U_0 - p.sol.lambda)],
                         [L_0],
                         [U_0],
                         [L_0],
                         Vector{O}(undef, 1),

                         Vector{Int}[],
                         Float64[],
                         Float64[],
                         Float64[],
                         Float64[],
                         Float64[],
                         A[],
                         discount(p.pomdp)
                 )
end

function expand!(D::DESPOT, b::Int, p::PL_DESPOTPlanner)
    S = statetype(p.pomdp)
    A = actiontype(p.pomdp)
    O = obstype(p.pomdp)
    odict = Dict{O, Int}()

    belief = get_belief(D, b, p.rs)
    for a in actions(p.pomdp, belief)
        empty!(odict)
        rsum = 0.0

        for scen in D.scenarios[b]
            rng = get_rng(p.rs, first(scen), D.Delta[b])
            s = last(scen)
            if !isterminal(p.pomdp, s)
                sp, o, r = @gen(:sp, :o, :r)(p.pomdp, s, a, rng)
                rsum += r
                bp = get(odict, o, 0)
                if bp == 0
                    push!(D.scenarios, Vector{Pair{Int, S}}())
                    bp = length(D.scenarios)
                    odict[o] = bp
                end
                push!(D.scenarios[bp], first(scen)=>sp)
            end
        end

        push!(D.ba_children, collect(values(odict)))
        ba = length(D.ba_children)
        push!(D.ba_action, a)
        push!(D.children[b], ba)
        rho = rsum*discount(p.pomdp)^D.Delta[b]/p.sol.K - p.sol.lambda
        push!(D.ba_rho, rho)
        push!(D.ba_Rsum, rsum)

        nbps = length(odict)
        resize!(D, length(D.children) + nbps)
        for (o, bp) in odict
            D.obs[bp] = o
            D.children[bp] = Int[]
            D.parent_b[bp] = b
            D.parent[bp] = ba
            D.Delta[bp] = D.Delta[b]+1

            scenario_belief = get_belief(D, bp, p.rs)
            L_0, U_0 = bounds(p.bounds, p.pomdp, scenario_belief)

            if p.sol.bounds_warnings
                bounds_sanity_check(p.pomdp, scenario_belief, L_0, U_0)
            end

            l_0 = length(D.scenarios[bp])/p.sol.K * discount(p.pomdp)^D.Delta[bp] * L_0
            mu_0 = max(l_0, length(D.scenarios[bp])/p.sol.K * discount(p.pomdp)^D.Delta[bp] * U_0 - p.sol.lambda)

            D.mu[bp] = mu_0
            D.U[bp] = U_0
            D.l[bp] = l_0 # = max(l_0, l_0 - p.sol.lambda)
            D.l_0[bp] = l_0
        end

        push!(D.ba_mu, D.ba_rho[ba] + sum(D.mu[bp] for bp in D.ba_children[ba]))
        push!(D.ba_l, D.ba_rho[ba] + sum(D.l[bp] for bp in D.ba_children[ba]))
        push!(D.ba_U, (D.ba_Rsum[ba] + discount(p.pomdp) * sum(length(D.scenarios[bp]) * D.U[bp] for bp in D.ba_children[ba]))/length(D.scenarios[b]))

        # sum_mu = 0.0
        # sum_l = 0.0
        # weighted_sum_U = 0.0
        # for bp in D.ba_children[ba]
        #     sum_mu += D.mu[bp]
        #     sum_l += D.l[bp]
        #     weighted_sum_U += length(D.scenarios[bp]) * D.U[bp]
        # end
        # push!(D.ba_mu, D.ba_rho[ba] + sum_mu)
        # push!(D.ba_l, D.ba_rho[ba] + sum_l)
        # push!(D.ba_U, (D.ba_Rsum[ba] + discount(p.pomdp) * weighted_sum_U)/length(D.scenarios[b]))
    end
end

function get_belief(D::DESPOT, b::Int, rs::DESPOTRandomSource)
    if isassigned(D.obs, b)
        ScenarioBelief(D.scenarios[b], rs, D.Delta[b], D.obs[b])
    else
        ScenarioBelief(D.scenarios[b], rs, D.Delta[b], missing)
    end
end

function Base.resize!(D::DESPOT, n::Int)
    resize!(D.children, n)
    resize!(D.parent_b, n)
    resize!(D.parent, n)
    resize!(D.Delta, n)
    resize!(D.mu, n)
    resize!(D.l, n)
    resize!(D.U, n)
    resize!(D.l_0, n)
    resize!(D.obs, n)
end
