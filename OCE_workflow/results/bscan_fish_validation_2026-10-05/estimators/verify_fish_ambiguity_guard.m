function verify_fish_ambiguity_guard()
% Verify the new conservative gap guard leaves the frozen fish maps intact.
    here=fileparts(mfilename('fullpath')); primary=load(fullfile(here,'fish_estimator_products.mat'),'fused','frozen');
    rows=struct([]); collections={primary.fused}; labels={"primary"};
    second=fullfile(here,'fish_noise2_fusion_products.mat');
    if isfile(second)
        s=load(second,'results'); collections{2}=s.results; labels{2}="noise2";
    end
    for realization=1:numel(collections)
        for family=1:2
            fused=collections{realization}{family}; n=numel(fused.per_excitation_results);
            c=NaN([size(fused.speed_m_s),n]);
            for source=1:n, c(:,:,source)=fused.per_excitation_results{source}.speed_m_s; end
            slowness=1./c; anchor=median(slowness,3,'omitnan');
            tol=primary.frozen.fusion.max_relative_slowness_deviation;
            near=sum(abs(slowness-anchor)<=.5*tol*anchor,3);
            newlyRejected=fused.valid_mask&near==0;
            assert(~any(newlyRejected,'all'),'Gap guard changes a published fish measurement.');
            if family==1, method="phase_gradient"; else, method="directional_phase"; end
            row=struct('realization',labels{realization},'method',method, ...
                'original_accepted_count',nnz(fused.valid_mask), ...
                'new_gap_rejected_count',nnz(newlyRejected), ...
                'minimum_measurements_near_median_anchor',min(near(fused.valid_mask)));
            if isempty(rows), rows=row; else, rows(end+1)=row; end %#ok<AGROW>
        end
    end
    metrics=struct2table(rows); writetable(metrics,fullfile(here,'fish_ambiguity_guard_check.csv')); disp(metrics);
end
