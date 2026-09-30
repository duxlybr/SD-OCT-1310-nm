function options = getDefaultSampleOpticalOptions(profile)
%GETDEFAULTSAMPLEOPTICALOPTIONS Build editable sample-optics defaults.

    switch profile
        case {"in_vivo_eye", "ex_vivo_eye"}
            source = "maintained_profile_default";
        case "phantom"
            source = "maintained_profile_default_material_override_required";
    end

    options = struct('refractive_index', struct( ...
        'value', 1.4, 'source', source));
end
