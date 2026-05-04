# title: Bar Chart
# description: Average tip by gender

data(tips()) *
    mapping(:sex, :tip) *
    visual(BarPlot)
