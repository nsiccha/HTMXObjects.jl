using PrecompileTools: @setup_workload, @compile_workload

# A small package-owned surface exercises metadata-driven forms without
# registering a router, starting a server, or executing an application job.
@htmx struct _PrecompileSurface
    @get preview(count::Int=1) = h.p(string(count))
end

@setup_workload let rows = [(; id=i, name="row $i", amount=i / 10) for i in 1:2]
    @compile_workload begin
        table = master_detail_table(["Name", "Amount"], rows;
            key=x -> x.id, master=x -> h.tr(h.td(x.name), number_cell(x.amount)),
            detail=x -> h.p(x.name), id="precompile-table")
        repr(MIME"text/html"(), table)
        repr(MIME"text/markdown"(), table)
        try
            surface = semantic_app(_PrecompileSurface())
            for runtime in (:inline, :linked)
                page = htmx(surface; runtime, assets="/vendor")
                repr(MIME"text/html"(), page)
            end
        finally
            # semantic_app retains its root for later operations. A workload
            # has no later request: never serialize its synthetic root state.
            delete!(_root_providers, _PrecompileSurface)
            delete!(_semantic_root_types, _PrecompileSurface)
            delete!(_property_descriptors_memo.entries, _PrecompileSurface)
            delete!(_semantic_descriptor_memo.entries, _PrecompileSurface)
        end
    end
end
