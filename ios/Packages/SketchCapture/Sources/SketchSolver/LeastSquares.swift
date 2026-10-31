import Foundation

/// A small Levenberg-Marquardt fitter for the corner coordinates of a room with unsquare corners
/// (spec F14 1.4: "solved by least squares on its corner coordinates"). A room has a handful of
/// corners, so the dense normal equations and a numeric Jacobian are plenty, and the damping
/// keeps the step sane when a diagonal leaves a direction undetermined: such a direction simply
/// stays where the rectilinear start put it.
enum LeastSquares {
  /// Minimises the squared norm of `residuals(parameters)` from `initial`. Returns the best
  /// parameters found; `initial` itself when nothing improves on it.
  static func fit(
    initial: [Double], maxIterations: Int = 100, residuals: ([Double]) -> [Double]
  ) -> [Double] {
    var parameters = initial
    var current = residuals(parameters)
    var cost = sumOfSquares(current)
    var lambda = 1e-3
    guard !parameters.isEmpty, !current.isEmpty else { return parameters }

    for _ in 0..<maxIterations {
      let jacobian = numericJacobian(at: parameters, value: current, residuals: residuals)
      let normal = normalMatrix(jacobian)
      let gradient = gradientVector(jacobian, current)
      var improved = false
      var step: [Double] = []
      for _ in 0..<12 {
        var damped = normal
        for i in damped.indices {
          damped[i][i] += lambda * max(damped[i][i], 1e-9)
        }
        guard let delta = solve(damped, gradient.map { -$0 }) else {
          lambda *= 10
          continue
        }
        let candidate = zip(parameters, delta).map(+)
        let candidateResiduals = residuals(candidate)
        let candidateCost = sumOfSquares(candidateResiduals)
        if candidateCost < cost {
          parameters = candidate
          current = candidateResiduals
          let gain = cost - candidateCost
          cost = candidateCost
          lambda = max(lambda / 3, 1e-12)
          step = delta
          improved = true
          if gain <= 1e-12 * (1 + cost) { return parameters }
          break
        }
        lambda *= 10
      }
      guard improved else { return parameters }
      if step.allSatisfy({ abs($0) < 1e-7 }) { return parameters }
    }
    return parameters
  }

  private static func sumOfSquares(_ values: [Double]) -> Double {
    values.reduce(0) { $0 + $1 * $1 }
  }

  /// Central differences; the residuals are smooth in the corner coordinates.
  private static func numericJacobian(
    at parameters: [Double], value: [Double], residuals: ([Double]) -> [Double]
  ) -> [[Double]] {
    let h = 1e-2
    var columns: [[Double]] = []
    for index in parameters.indices {
      var forward = parameters
      forward[index] += h
      var backward = parameters
      backward[index] -= h
      let plus = residuals(forward)
      let minus = residuals(backward)
      columns.append(zip(plus, minus).map { ($0 - $1) / (2 * h) })
    }
    // Transpose to rows = residuals, columns = parameters.
    var rows = [[Double]](repeating: [Double](repeating: 0, count: parameters.count), count: value.count)
    for (column, values) in columns.enumerated() {
      for (row, entry) in values.enumerated() where row < rows.count {
        rows[row][column] = entry
      }
    }
    return rows
  }

  private static func normalMatrix(_ jacobian: [[Double]]) -> [[Double]] {
    let count = jacobian.first?.count ?? 0
    var result = [[Double]](repeating: [Double](repeating: 0, count: count), count: count)
    for row in jacobian {
      for i in 0..<count {
        for j in 0..<count {
          result[i][j] += row[i] * row[j]
        }
      }
    }
    return result
  }

  private static func gradientVector(_ jacobian: [[Double]], _ residuals: [Double]) -> [Double] {
    let count = jacobian.first?.count ?? 0
    var result = [Double](repeating: 0, count: count)
    for (row, residual) in zip(jacobian, residuals) {
      for i in 0..<count {
        result[i] += row[i] * residual
      }
    }
    return result
  }

  /// Gaussian elimination with partial pivoting; nil when the system is singular.
  private static func solve(_ matrix: [[Double]], _ rhs: [Double]) -> [Double]? {
    let n = rhs.count
    var a = matrix
    var b = rhs
    for column in 0..<n {
      var pivot = column
      for row in column..<n where abs(a[row][column]) > abs(a[pivot][column]) {
        pivot = row
      }
      guard abs(a[pivot][column]) > 1e-15 else { return nil }
      if pivot != column {
        a.swapAt(pivot, column)
        b.swapAt(pivot, column)
      }
      for row in (column + 1)..<n {
        let factor = a[row][column] / a[column][column]
        guard factor != 0 else { continue }
        for k in column..<n {
          a[row][k] -= factor * a[column][k]
        }
        b[row] -= factor * b[column]
      }
    }
    var x = [Double](repeating: 0, count: n)
    for row in stride(from: n - 1, through: 0, by: -1) {
      var sum = b[row]
      for k in (row + 1)..<n {
        sum -= a[row][k] * x[k]
      }
      x[row] = sum / a[row][row]
    }
    return x.allSatisfy(\.isFinite) ? x : nil
  }
}
