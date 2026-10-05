function compare_fish_individual_and_fusion(outputPath)
% Compare each independent map to fusion on EXACTLY their common support.
    here=fileparts(mfilename('fullpath')); if nargin<1, outputPath=here; end
    s=load(fullfile(outputPath,'fish_estimator_products.mat')); rows=struct([]);
    for family=1:2
        if family==1, method="phase_gradient"; else, method="directional_phase"; end
        fused=s.fused{family};
        for excitation=1:8
            separate=fused.per_excitation_results{excitation};
            common=separate.valid_mask&fused.valid_mask&s.truthMask;
            independentError=median(abs(separate.speed_m_s(common)./s.truth(common)-1));
            fusionError=median(abs(fused.speed_m_s(common)./s.truth(common)-1));
            row=struct('method',method,'excitation_angle_deg',(excitation-1)*45, ...
                'common_support_count',nnz(common), ...
                'individual_median_absolute_relative_speed_error',independentError, ...
                'fusion_median_absolute_relative_speed_error',fusionError, ...
                'error_reduction_fraction',(independentError-fusionError)/independentError);
            if isempty(rows), rows=row; else, rows(end+1)=row; end %#ok<AGROW>
        end
    end
    table=struct2table(rows);
    writetable(table,fullfile(outputPath,'fish_individual_fusion_common_support.csv')); disp(table);
end
