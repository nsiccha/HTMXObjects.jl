# title: Heatmap
# description: Correlation matrix

data(cars()) *
    mapping(:horsepower, :mpg) *
    visual(Heatmap)
