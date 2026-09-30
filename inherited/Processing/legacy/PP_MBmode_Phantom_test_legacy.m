function [] = PP_MBmode_Phantom_test_legacy(varargin)
%PP_MBMODE_PHANTOM_TEST_LEGACY Legacy entry point for the original processing script.
%
% This file intentionally forwards all inputs to Processing/PP_MBmode_Phantom_test.m.
% The original file remains untouched and is the authoritative legacy workflow.
%
% Usage:
%   PP_MBmode_Phantom_test_legacy(filename, filepath, OCE_params)

    PP_MBmode_Phantom_test(varargin{:});
end
