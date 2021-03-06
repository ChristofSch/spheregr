methods <- c("linfre", "lincos", "lingeo", "locfre", "trifre", "locgeo", "trigeo")


spiral_fun <- function(theta_min, theta_max = theta_min, phi_start = 0.5, circles = 1) {
  force(theta_min)
  force(theta_max)
  force(phi_start)
  force(circles)
  function(x) {
    phi <- (phi_start + x * 2 * pi * circles) %% (2 * pi)
    theta <- theta_min + x * (theta_max - theta_min)
    m_a <- cbind(theta, phi)
    list(m=convert_a2e(m_a), m_a=m_a)
  }
}


geodesic_fun <- function(speed_bounds=NULL, p=NULL, v=NULL) {
  force(p)
  force(v)
  speed_target <-
    if (length(speed_bounds) == 2) {
      runif(1, min = speed_bounds[1], max = speed_bounds[2])
    } else {
      speed_bounds
    }
  if (is.null(p) || is.null(v)) {
    p_a <- matrix(runif(2) * c(pi, 2 * pi), ncol=2)
    p <- convert_a2e(p_a)
    v <- norm_vec(t(pracma::nullspace(p) %*% rnorm(2))) * speed_target
  } else {
    if (!is.null(speed_target)) v <- v * speed_target / sqrt(sum(v^2))
  }
  function(x) {
    m <- Exp(p, x %*% v)
    list(m=m, m_a=convert_e2a(m))
  }
}



sample_regression_data <- function(n,
                                   n_new,
                                   sd,
                                   noise = c("contracted", "normal"),
                                   curve = c("geodesic", "spiral"),
                                   ...) {
  x_new <- seq(0, 1, len = n_new)
  x <- seq(0, 1, len = n)
  curve <- match.arg(curve)
  m_fun <- switch(curve,
                  geodesic = geodesic_fun(...),
                  spiral = spiral_fun(...))
  m <- m_fun(x)
  m_new <- m_fun(x_new)
  noise <- match.arg(noise)
  y <- switch(noise,
              contracted = add_noise_contract(m$m, sd = sd),
              normal = add_noise_normal(m$m, sd = sd))
  list(
    x = x,
    x_new = x_new,
    y = y,
    y_a = convert_e2a(y),
    m = m$m,
    m_a = m$m_a,
    m_new = m_new$m,
    m_new_a = m_new$m_a
  )
}


estimate <- function(method = methods, ...) {
  method <- match.arg(method)
  switch(method,
         linfre = estimate_linfre(...),
         lincos = estimate_lincos(...),
         lingeo = estimate_lingeo(...),
         locfre = estimate_locfre(...),
         trifre = estimate_trifre(...),
         locgeo = estimate_locgeo(...),
         trigeo = estimate_trigeo(...)
  )
}


simu_run_one <- function(osamp, ometh, verbosity=1) {
  data <- do.call(sample_regression_data, osamp)
  res <- list()
  opt_data <- data[c("x", "y", "x_new")]
  for (meth in names(ometh)) {
    if (verbosity > 2) {
      cat("\t\t", meth, " ", sep="")
      pt <- proc.time()
    }
    res[[meth]] <-
      do.call(estimate, c(ometh[[meth]], opt_data, list(method = meth)))
    if (verbosity > 2) {
      cat((proc.time() - pt)[3], "\n")
    }
  }
  list(data=data, predict=res)
}

#' @export
create_opt <- function(
  reps, n, sd, n_new,
  curve = c("spiral_closed", "spiral_open", "geodesic"),
  geo_speed = pi, geo_p = NULL, geo_v = NULL,
  accuracy = 0.25, grid_size = 3,
  methods=NULL, method_opts=NULL) {

  o <- list(samp = list(),
            simu = list(),
            meth = list())

  o$simu$reps <- reps

  o$samp$n <- n
  o$samp$n_new <- n_new
  o$samp$noise <- "contracted"
  o$samp$sd <- sd

  curve <- match.arg(curve)
  o$simu$curve <- curve
  switch(curve,
         spiral_closed = {
           o$samp$curve <- "spiral"
           o$samp$theta_min <- pi/4
           o$samp$theta_max <- pi/4
           o$samp$phi_start <- 0.5
           o$samp$circles <- 1
           periodic <- TRUE
         },
         spiral_open = {
           o$samp$curve <- "spiral"
           o$samp$theta_min <- pi/8
           o$samp$theta_max <- pi/8*7
           o$samp$phi_start <- 0.5
           o$samp$circles <- 1.5
           periodic <- FALSE
         },
         geodesic = {
           o$samp$curve <- "geodesic"
           o$samp$speed_bounds <- geo_speed
           o$samp$p <- geo_p
           o$samp$v <- geo_v
           if (abs((pi + geo_speed) %% (2*pi) - pi) < 0.01) periodic <- TRUE
           else periodic <- FALSE
           o$samp
         }
  )

  methods <- unique(c(methods, names(method_opts)))
  ometh <- lapply(methods, function(meth) {
    default_opts <- switch(
      meth,
      locfre = list(
        adapt = "loocv",
        kernel = "epanechnikov",
        bw = 7,
        grid_size = grid_size
      ),
      trifre = list(
        adapt = "loocv",
        num_basis = 20,
        periodize = !periodic,
        grid_size =  grid_size
      ),
      locgeo = list(
        adapt = "loocv",
        bw = 7,
        kernel = "epanechnikov",
        max_speed = 5,
        grid_size = grid_size,
        accuracy = accuracy
      ),
      trigeo = list(
        adapt = "none",
        num_basis = 3,
        periodize = !periodic,
        max_speed = 5,
        grid_size = grid_size,
        accuracy = accuracy
      ),
      linfre = list(grid_size = grid_size),
      lincos = list(max_speed = 10,
                    grid_size = grid_size),
      lingeo = list(max_speed = 10,
                    grid_size = grid_size)
    )

    opts <- default_opts
    opts[names(method_opts[[meth]])] <- method_opts[[meth]]
    opts
  })

  names(ometh) <- methods
  o$meth <- ometh

  o
}


#' @export
simulate <- function(opt_list, verbosity=1, seed=NULL) {
  if (!is.null(seed)) {
    set.seed(seed)
  }
  all_res <- list()
  for (i in seq_along(opt_list)) {
    opt <- opt_list[[i]]
    if (verbosity > 0) {
      cat("start opt", i,"/", length(opt_list),"\n")
      cat("\truns: ", opt$simu$reps, "\n")
      cat("\tn: ", opt$samp$n, "\n")
      pto <- proc.time()
    }
    res <- list()
    for (j in seq_len(opt$simu$reps)) {
      if (verbosity > 1) {
        cat("\tstart run", j,"/", opt$simu$reps, "\n")
        pt <- proc.time()
      }
      res[[j]] <- simu_run_one(opt$samp, opt$meth, verbosity)
      if (verbosity > 1) {
        cat("\t\ttotal:", (proc.time() - pt)[3], "\n")
        cat("\tend run", j,"/", opt$simu$reps,"\n")
      }
    }
    all_res[[i]] <- res
    if (verbosity > 0) {
      cat("\ttime:", (proc.time() - pto)[3], "\n")
      cat("end opt", i,"/", length(opt_list),"\n")
    }
  }
  all_res
}


#' Simulate using package parallel
#'
#' Repetitions of each setting a run in parallel.
#'
#' @export
simulate_parallel <- function(opt_list, cores=parallel::detectCores(), seed=NULL) {
  cl <- parallel::makeCluster(cores)
  if (!is.null(seed)) {
    set.seed(seed)
    parallel::clusterSetRNGStream(cl, seed)
  }
  all_res <- lapply(opt_list, function(opt) {
    parallel::parLapply(
      cl,
      seq_len(opt$simu$reps),
      function(i) simu_run_one(osamp=opt$samp, ometh=opt$meth, verbosity=0))
  })
  parallel::stopCluster(cl)
  all_res
}

