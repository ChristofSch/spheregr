% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/lincos.R
\name{cos_estim_speed}
\alias{cos_estim_speed}
\title{Estimate lambda of the (1D) cosine regression.}
\usage{
cos_estim_speed(x, y, q, max_speed, grid_size)
}
\arguments{
\item{x}{double(n) in \link{0,1}, covariates.}

\item{y}{nx3 matrix, observations on sphere.}

\item{q}{kx3 matrix, test points on sphere.}
}
\value{
double(1), estimated lambda
}
\description{
Estimate lambda of the (1D) cosine regression.
}
