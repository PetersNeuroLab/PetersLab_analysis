# Analysis
Code for common analysis

## Finding recordings
`plab.find_recordings(animal,day,workflow)`: find recordings (specific or general) and recording modalities

## Widefield 
Call functions from `plab.wf.(function)`:

`batch_widefield_preprocess`: run on widefield computer after experiment, calls `preprocess_widefield` for all local data
`hemo_correct(U_neuro,V_neuro,t_neuro,U_hemo,V_hemo,t_hemo)`: apply hemodynamic correction from alternating blue/violet
`svd2px(U,V)`: reconstruct pixels from SVD components
`svd_dff(U,V,mean_image)`: make deltaF/F V from SVD components
`change_U(U,V,newU)`: convert V from one set of U's to another
