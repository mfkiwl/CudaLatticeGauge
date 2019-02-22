# CudaLatticeGauge

lattice gauge simulation with CUDA

Only support SM60+ (most part support SM35+, but for atomic add double is supported only in SM60)

Testing on GTX-1060 (6G)

Using GMRES with 10 orthrognal basis, maximum supported (32 x 32 x 32 x 16)
For the release built
One trajectory with 50 Omelyan sub-steps cost about 470 secs
(The speed is related with kappa and beta, 470secs is tested using kappa=0.1355 and beta=2.5, 
GMRES with 10 orthrognal basis will converge with about 3 restarts)

See detailed.pdf


