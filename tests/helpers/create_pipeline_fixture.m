function fixture = create_pipeline_fixture()
%CREATE_PIPELINE_FIXTURE Build lightweight synthetic pipeline test inputs.

    fixture.io = create_io_acquisition_fixture();
    oce.io.loadExperimentalLog( ...
        fixture.io.logPath, 'SaveAcquisitionParams', true);
    fixture.resultsRoot = tempname;
    mkdir(fixture.resultsRoot);
    fixture.resultsCleanup = onCleanup(@() remove_tree(fixture.resultsRoot));
    fixture.results = create_results_fixture(fixture.resultsRoot);
end

function remove_tree(folder)
    if isfolder(folder)
        rmdir(folder, 's');
    end
end
